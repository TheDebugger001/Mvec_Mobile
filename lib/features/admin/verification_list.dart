import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../widgets/common.dart';

const _quickReasons = [
  'The logo is missing or unclear.',
  'The phone number could not be reached.',
  'The business description is too short to understand what you sell.',
  'The location is incomplete: add your district and sector.',
  'The business name does not match the documents or products.',
];

List<(String, String)> _checklist(Map<String, dynamic> p) {
  final loc = p['location'] is Map ? asMap(p['location']).values.where((x) => strOf(x).isNotEmpty).join(', ') : strOf(p['location']);
  return [
    ('Business name', strOf(p['businessName'])),
    ('Phone', strOf(p['phone'])),
    ('Email', strOf(p['email'])),
    ('Description', strOf(p['description']).length >= 20 ? strOf(p['description']) : ''),
    ('Logo', strOf(p['logoUrl'])),
    ('Category', strOf(p['category'])),
    ('Location', loc),
  ];
}

/// Seller or supplier verification list with review sheet (`VerificationList`).
class VerificationList extends StatefulWidget {
  const VerificationList({super.key, required this.kind});
  final String kind; // seller | supplier

  @override
  State<VerificationList> createState() => _VerificationListState();
}

class _VerificationListState extends State<VerificationList> {
  String _tab = 'PENDING';
  int _page = 1;
  String get _path => widget.kind == 'seller' ? '/admin/vendors' : '/admin/suppliers';
  late Loader<Map<String, dynamic>> _list = _loadList();
  late final _counts = Loader(
    () async => [
      for (final s in ['PENDING', 'VERIFIED', 'REJECTED']) numOf(asMap((await jget(_path, {'verificationStatus': s, 'pageSize': 1}))['meta'])['total']).toInt(),
    ],
  );

  Loader<Map<String, dynamic>> _loadList() => Loader(() => jget(_path, {'page': _page, 'pageSize': 20, if (_tab != 'ALL') 'verificationStatus': _tab}));

  void _reload() {
    final old = _list;
    setState(() => _list = _loadList());
    old.dispose();
    _counts.reload();
  }

  @override
  void dispose() {
    _list.dispose();
    _counts.dispose();
    super.dispose();
  }

  Future<void> _review(Map<String, dynamic> p) async {
    final done = await Navigator.of(context, rootNavigator: true).push<String>(MaterialPageRoute(builder: (_) => _ReviewPage(kind: widget.kind, profile: p)));
    if (done != null && mounted) {
      toast(context, done);
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Tiny('Review new and updated profiles. They are notified of your decision by message, SMS and email.'),
        ListenableBuilder(
          listenable: _counts,
          builder: (context, _) {
            final c = _counts.data ?? const [];
            return TabChips(
              tabs: const [('PENDING', 'Waiting'), ('VERIFIED', 'Verified'), ('REJECTED', 'Needs changes'), ('ALL', 'All')],
              value: _tab,
              counts: c.length == 3 ? {'PENDING': c[0], 'VERIFIED': c[1], 'REJECTED': c[2]} : null,
              onChanged: (v) {
                _tab = v;
                _page = 1;
                _reload();
              },
            );
          },
        ),
        LoadView(
          loader: _list,
          builder: (d) {
            final rows = asMaps(d['data']);
            final total = numOf(asMap(d['meta'])['total'], rows.length).toInt();
            if (rows.isEmpty) {
              return EmptyState(
                icon: Icons.verified_outlined,
                title: _tab == 'PENDING' ? 'Nobody is waiting' : 'No profiles here',
                message: _tab == 'PENDING' ? 'New profiles appear here, and you also get a notification.' : null,
              );
            }
            return Column(
              children: [
                for (final p in rows)
                  Builder(
                    builder: (_) {
                      final missing = _checklist(p).where((c) => c.$2.isEmpty).length;
                      return RecordCard(
                        leading: ProductImage(src: strOf(p['logoUrl']), size: 46, radius: 10),
                        title: strOf(p['businessName']),
                        subtitle: [personName(p['user'], ''), strOf(p['email']), strOf(p['phone'])].where((x) => x.isNotEmpty).join(' · '),
                        lines: [
                          '${strOf(p['category'], 'No category')}${widget.kind == 'seller' ? ' · ${numOf(p['productCount']).toInt()} products' : ''} · updated ${formatDate(p['updatedAt'])}',
                          if (strOf(p['verificationNote']).isNotEmpty) 'Asked to fix: ${p['verificationNote']}',
                          if (missing > 0) '$missing item${missing == 1 ? '' : 's'} missing',
                        ],
                        status: Pill(p['verificationStatus'], label: p['verificationStatus'] == 'PENDING' ? 'Waiting' : null),
                        badges: [if (p['status'] != 'ACTIVE' && p['status'] != null) Pill(p['status'])],
                        actions: [ActionChipBtn(p['verificationStatus'] == 'PENDING' ? 'Review' : 'Open', primary: p['verificationStatus'] == 'PENDING', onPressed: () => _review(p))],
                      );
                    },
                  ),
                if (total > 20)
                  PaginationBar(
                    page: _page,
                    total: total,
                    perPage: 20,
                    onPage: (n) {
                      _page = n;
                      _reload();
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

class _ReviewPage extends StatefulWidget {
  const _ReviewPage({required this.kind, required this.profile});
  final String kind;
  final Map<String, dynamic> profile;

  @override
  State<_ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<_ReviewPage> {
  late final _history = Loader(() => jlist('/admin/audit-logs', 'data', {'targetId': idOf(widget.profile), 'pageSize': 10}));
  final _reason = TextEditingController();
  String _busy = '';

  @override
  void dispose() {
    _history.dispose();
    _reason.dispose();
    super.dispose();
  }

  String get _base => widget.kind == 'seller' ? '/admin/vendors/${idOf(widget.profile)}' : '/admin/suppliers/${idOf(widget.profile)}';
  String get _name => strOf(widget.profile['businessName']);

  Future<void> _decide(String decision) async {
    if (decision == 'REJECTED' && _reason.text.trim().length < 5) {
      toast(context, 'Write what the ${widget.kind} must fix. They will see it.', error: true);
      return;
    }
    setState(() => _busy = decision);
    try {
      await jpatch('$_base/verify', {'decision': decision, 'reason': _reason.text.trim()});
      if (mounted) Navigator.of(context).pop(decision == 'VERIFIED' ? '$_name is verified and has been notified.' : '$_name was told what to fix.');
    } catch (e) {
      if (mounted) {
        toast(context, errorText(e), error: true);
        setState(() => _busy = '');
      }
    }
  }

  Future<void> _status(String status) async {
    if (!await confirmDialog(
      context,
      status == 'ACTIVE' ? 'Reactivate $_name?' : 'Suspend $_name? They cannot sell${widget.kind == 'supplier' ? ' to vendors' : ''} while suspended.',
      danger: status != 'ACTIVE',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = status);
    try {
      await jpatch('$_base/status', {'status': status});
      if (mounted) Navigator.of(context).pop(status == 'ACTIVE' ? '$_name is active again.' : '$_name is suspended.');
    } catch (e) {
      if (mounted) {
        toast(context, errorText(e), error: true);
        setState(() => _busy = '');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final items = _checklist(p);
    final missing = items.where((c) => c.$2.isEmpty).map((c) => c.$1).toList();
    final reasons = [if (missing.isNotEmpty) 'Please complete: ${missing.join(', ')}.', ..._quickReasons];
    return Scaffold(
      appBar: AppBar(title: Text('${widget.kind == 'seller' ? 'Seller' : 'Supplier'} verification')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Row(
              children: [
                ProductImage(src: strOf(p['logoUrl']), size: 60, radius: 12),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_name, style: context.mvH1.copyWith(fontSize: 18)),
                      Tiny('${personName(p['user'], '')} · joined ${formatDate(p['createdAt'])}'),
                      Wrap(spacing: 6, children: [Pill(p['verificationStatus']), if (p['status'] != 'ACTIVE' && p['status'] != null) Pill(p['status'])]),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            missing.isEmpty ? const Notice(ok: true, text: 'The profile is complete. Check the details look genuine before verifying.') : Notice(text: 'Missing or too short: ${missing.join(', ')}.'),
            DataCard(
              child: Column(
                children: [
                  for (final (k, v) in items)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(v.isNotEmpty ? Icons.check_circle_rounded : Icons.cancel_rounded, color: v.isNotEmpty ? MvColors.successText : MvColors.errorText, size: 20),
                      title: Text(k, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(v.isNotEmpty ? (v.length > 140 ? '${v.substring(0, 140)}…' : v) : 'Not provided'),
                    ),
                  if (widget.kind == 'seller')
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.info_outline_rounded, size: 20),
                      title: const Text('Products', style: TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(numOf(p['productCount']) > 0 ? '${p['productCount']} listed' : 'None listed yet (not needed to verify)'),
                    ),
                ],
              ),
            ),
            if (widget.kind == 'seller' && strOf(p['slug']).isNotEmpty)
              OutlineBtn(label: 'Open the public store page', icon: Icons.open_in_new_rounded, compact: true, onPressed: () => context.push('/vendors/${p['slug']}')),
            if (strOf(p['verificationNote']).isNotEmpty) InfoBox(title: 'Last rejection reason', text: strOf(p['verificationNote'])),
            const SizedBox(height: 10),
            TextField(
              controller: _reason,
              minLines: 3,
              maxLines: 5,
              maxLength: 500,
              decoration: InputDecoration(labelText: 'Reason if you reject (the ${widget.kind} sees this)', hintText: 'What should they fix?'),
            ),
            Wrap(spacing: 6, runSpacing: 6, children: [for (final r in reasons) ActionChip(label: Text(r, style: const TextStyle(fontSize: 12)), onPressed: () => setState(() => _reason.text = r))]),
            const SizedBox(height: 14),
            GradientButton(label: 'Verify', loading: _busy == 'VERIFIED', onPressed: _busy.isNotEmpty ? null : () => _decide('VERIFIED')),
            const SizedBox(height: 8),
            OutlineBtn(label: 'Reject with reason', loading: _busy == 'REJECTED', onPressed: _busy.isNotEmpty ? null : () => _decide('REJECTED')),
            const SizedBox(height: 8),
            p['status'] == 'ACTIVE'
                ? OutlineBtn(label: 'Suspend', danger: true, onPressed: _busy.isNotEmpty ? null : () => _status('SUSPENDED'))
                : OutlineBtn(label: 'Reactivate', onPressed: _busy.isNotEmpty ? null : () => _status('ACTIVE')),
            ListenableBuilder(
              listenable: _history,
              builder: (context, _) {
                final h = _history.data ?? const [];
                if (h.isEmpty) return const SizedBox.shrink();
                return Section(
                  title: 'History',
                  children: [
                    for (final x in h)
                      Tiny('${formatDateTime(x['at'])} · ${x['actor']}: ${x['action']}${strOf(asMap(x['detail'])['reason']).isNotEmpty ? ' (“${asMap(x['detail'])['reason']}”)' : ''}'),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
