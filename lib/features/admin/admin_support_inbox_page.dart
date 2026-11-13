import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/format.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../portal/shared_pages.dart' show openTicketAsStaff, supportChip;
import '../../widgets/common.dart';

const _supportRole = {'buyer': 'Buyer', 'vendor': 'Seller', 'supplier': 'Supplier', 'affiliate': 'Affiliate', 'delivery': 'Courier'};

/// `/admin/support` — requests from every kind of account.
class AdminSupportInboxPage extends StatefulWidget {
  const AdminSupportInboxPage({super.key, this.openCase});
  final String? openCase;

  @override
  State<AdminSupportInboxPage> createState() => _AdminSupportInboxPageState();
}

class _AdminSupportInboxPageState extends State<AdminSupportInboxPage> {
  late final _data = Loader(() => jlist('/support/cases', 'cases', {'pageSize': 100}));
  String _tab = 'ACTIVE';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _data.reload());
    final id = widget.openCase;
    if (id != null && id.isNotEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => openTicketAsStaff(context, id, onChanged: _data.reload));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _data.dispose();
    super.dispose();
  }

  bool _active(Map<String, dynamic> c) => ['OPEN', 'IN_PROGRESS'].contains(c['status']);

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'Communication',
      title: 'Support inbox',
      subtitle: 'Requests from buyers, sellers, suppliers, affiliates and couriers. Reply here; they are notified every time.',
      onRefresh: _data.reload,
      children: [
        LoadView(
          loader: _data,
          loadingLabel: 'Loading requests…',
          builder: (cases) {
            final shown =
                cases.where((c) => _tab == 'ACTIVE' ? _active(c) : c['status'] == _tab).toList()..sort((a, b) {
                  final u = (b['priority'] == 'URGENT' ? 1 : 0) - (a['priority'] == 'URGENT' ? 1 : 0);
                  return u != 0 ? u : (parseDate(b['updatedAt']) ?? DateTime(2000)).compareTo(parseDate(a['updatedAt']) ?? DateTime(2000));
                });
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TabChips(
                  tabs: const [('ACTIVE', 'Needs an answer'), ('RESOLVED', 'Resolved'), ('CLOSED', 'Closed')],
                  value: _tab,
                  counts: {'ACTIVE': cases.where(_active).length, 'RESOLVED': cases.where((c) => c['status'] == 'RESOLVED').length, 'CLOSED': cases.where((c) => c['status'] == 'CLOSED').length},
                  onChanged: (v) => setState(() => _tab = v),
                ),
                if (shown.isEmpty)
                  EmptyState(
                    icon: Icons.inbox_outlined,
                    title: _tab == 'ACTIVE' ? 'Inbox zero' : 'Nothing here',
                    message: _tab == 'ACTIVE' ? 'New requests appear here and in your notifications.' : null,
                  ),
                for (final c in shown)
                  Builder(
                    builder: (_) {
                      final by = asMap(c['openedBy']);
                      final replies = c['comments'] is List ? (c['comments'] as List).length : 0;
                      return RecordCard(
                        title: strOf(c['subject']),
                        subtitle: '${personName(by, '')} · ${_supportRole[by['role']] ?? by['role'] ?? ''} · ${titleCase(c['category'])} · ${c['ticketNumber'] ?? ''}',
                        lines: ['$replies repl${replies == 1 ? 'y' : 'ies'} · updated ${formatDateTime(c['updatedAt'])}'],
                        badges: [if (c['priority'] == 'URGENT' || c['priority'] == 'HIGH') StatusChip(titleCase(c['priority']), tone: c['priority'] == 'URGENT' ? StatusTone.bad : StatusTone.warn)],
                        status: supportChip(c['status']),
                        onTap: () => openTicketAsStaff(context, idOf(c), onChanged: _data.reload),
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

// ─── Refunds & withdrawals ──────────────────────────────────────────────────
