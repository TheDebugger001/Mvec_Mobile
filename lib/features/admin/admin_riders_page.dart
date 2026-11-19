import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../widgets/common.dart';

const _tabs = [('PENDING', 'To review'), ('APPROVED', 'Approved'), ('SUSPENDED', 'Suspended'), ('REJECTED', 'Rejected')];
const _vehicles = {'MOTORBIKE': 'Motorbike', 'BICYCLE': 'Bicycle', 'CAR': 'Car', 'ON_FOOT': 'On foot'};

/// `/admin/riders`: approve riders who signed up; reject or suspend with a
/// reason the rider sees (and gets by text message).
class AdminRidersPage extends StatefulWidget {
  const AdminRidersPage({super.key});

  @override
  State<AdminRidersPage> createState() => _AdminRidersPageState();
}

class _AdminRidersPageState extends State<AdminRidersPage> {
  String _tab = 'PENDING';
  String _busy = '';
  late Loader<List<Map<String, dynamic>>> _data = _load();

  Loader<List<Map<String, dynamic>>> _load() => Loader(() => jlist('/admin/riders', 'riders', {'status': _tab}));

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  Future<void> _review(Map<String, dynamic> r, String status) async {
    String? note;
    if (status != 'APPROVED') {
      final v = await showFormSheet<Map<String, dynamic>>(
        context,
        title: '${status == 'REJECTED' ? 'Reject' : 'Suspend'} ${strOf(r['name'])}',
        subtitle: 'The rider sees this reason.',
        fields: const [FieldSpec('note', 'Reason', type: FieldType.textarea, required: true)],
        initial: const {},
        submitLabel: status == 'REJECTED' ? 'Reject' : 'Suspend',
        danger: true,
        onSubmit: (v) async => v,
      );
      note = strOf(v?['note']);
      if (note.trim().isEmpty) return;
    }
    setState(() => _busy = idOf(r));
    try {
      await jpatch('/admin/riders/${idOf(r)}', {'status': status, if (note != null) 'note': note});
      if (mounted) toast(context, '${strOf(r['name'])} ${status.toLowerCase()}.');
      _data.reload();
    } catch (e) {
      if (mounted) toast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  @override
  Widget build(BuildContext context) => PortalPage(
        eyebrow: 'Ikiguzi operations',
        title: 'Riders',
        subtitle: 'Riders sign up in the app. Approve them before they can take deliveries.',
        onRefresh: _data.reload,
        children: [
          TabChips(
            tabs: _tabs,
            value: _tab,
            onChanged: (t) => setState(() {
              _tab = t;
              _data.dispose();
              _data = _load();
            }),
          ),
          LoadView(
            loader: _data,
            loadingLabel: 'Loading riders…',
            builder: (rows) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (rows.isEmpty) const EmptyState(icon: Icons.two_wheeler_outlined, title: 'No riders here'),
              for (final r in rows)
                RecordCard(
                  title: strOf(r['name']),
                  subtitle: strOf(r['phone']),
                  lines: ['${_vehicles[r['vehicleType']] ?? strOf(r['vehicleType'])}${strOf(r['plateNumber']).isEmpty ? '' : ' · ${r['plateNumber']}'}', if ((r['districts'] as List? ?? const []).isNotEmpty) (r['districts'] as List).join(', ') else if (strOf(r['district']).isNotEmpty) strOf(r['district']), if (r['isOnline'] == true) 'Online now'],
                  status: StatusChip.of(strOf(r['status'])),
                  actions: [
                    if (r['status'] != 'APPROVED') ActionChipBtn('Approve', busy: _busy == idOf(r), onPressed: () => _review(r, 'APPROVED')),
                    if (r['status'] == 'PENDING') ActionChipBtn('Reject', danger: true, busy: _busy == idOf(r), onPressed: () => _review(r, 'REJECTED')),
                    if (r['status'] == 'APPROVED') ActionChipBtn('Suspend', danger: true, busy: _busy == idOf(r), onPressed: () => _review(r, 'SUSPENDED')),
                  ],
                ),
            ]),
          ),
        ],
      );
}
