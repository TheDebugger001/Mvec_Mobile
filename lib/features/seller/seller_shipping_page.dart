import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/locations.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../widgets/common.dart';

int _coverageScore(Map<String, dynamic> z, String province, String district) {
  final ds = [for (final d in (z['districts'] is List ? z['districts'] as List : const [])) '$d'.toLowerCase()];
  final ps = [for (final p in (z['provinces'] is List ? z['provinces'] as List : const [])) '$p'.toLowerCase()];
  if (ds.isNotEmpty) return ds.contains(district.toLowerCase()) ? 3 : 0;
  if (ps.isNotEmpty) return ps.contains(province.toLowerCase()) ? 2 : 0;
  return 1;
}

Map<String, dynamic>? _zoneFor(List<Map<String, dynamic>> zones, String province, String district) {
  Map<String, dynamic>? best;
  var score = 0;
  for (final z in zones) {
    final s = _coverageScore(z, province, district);
    if (s > score || (s == score && s > 0 && best != null && numOf(z['fee']) < numOf(best['fee']))) {
      best = z;
      score = s;
    }
  }
  return best;
}

/// `/vendor/shipping` — delivery zones and fees per store, coverage map and
/// a test address.
class SellerShippingPage extends StatefulWidget {
  const SellerShippingPage({super.key});

  @override
  State<SellerShippingPage> createState() => _SellerShippingPageState();
}

class _SellerShippingPageState extends State<SellerShippingPage> {
  late final _data = Loader(() async {
    final r = await Future.wait([jlist('/shipping/zones/mine', 'data'), jlist('/stores/mine', 'stores').catchError((_) => <Map<String, dynamic>>[])]);
    return (zones: r[0], stores: r[1]);
  });
  String _storeTab = '';

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  Future<void> _edit(Map<String, dynamic>? z, String storeId) async {
    final saved = await Navigator.of(context, rootNavigator: true).push<String>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => _ZoneEditor(zone: z, storeId: storeId)));
    if (saved != null && mounted) {
      toast(context, saved);
      _data.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LoadView(
      loader: _data,
      page: true,
      builder: (d) {
        final stores = d.stores;
        final primary = stores.where((s) => s['isPrimary'] == true).firstOrNull ?? stores.firstOrNull;
        final active = _storeTab.isNotEmpty ? _storeTab : idOf(primary);
        final storeZones = d.zones.where((z) => idOf(z['store']) == active).toList();
        final effective = (storeZones.isNotEmpty ? storeZones : d.zones).where((z) => z['status'] == 'ACTIVE').toList();
        final usingOther = storeZones.isEmpty && d.zones.isNotEmpty;
        var uncovered = 0;
        for (final p in rwandaLocations.keys) {
          for (final dist in rwandaLocations[p]!) {
            if (_zoneFor(effective, p, dist) == null) uncovered++;
          }
        }
        return PortalPage(
          eyebrow: 'Seller platform',
          title: 'Shipping',
          subtitle: 'Delivery zones and fees per store. Checkout charges buyers these fees for their district, and the fees are paid to you in full.',
          onRefresh: _data.reload,
          action: stores.isEmpty ? null : GradientButton(label: 'Add zone', icon: Icons.add_rounded, compact: true, onPressed: () => _edit(null, active)),
          children: [
            if (stores.isEmpty) const EmptyState(icon: Icons.storefront_outlined, title: 'Register a store first', message: 'Shipping zones belong to a store.'),
            if (stores.isNotEmpty) ...[
              if (stores.length > 1)
                TabChips(
                  tabs: [for (final s in stores) (idOf(s), '${s['storeName']}${s['isPrimary'] == true ? ' ★' : ''}')],
                  value: active,
                  counts: {for (final s in stores) idOf(s): d.zones.where((z) => idOf(z['store']) == idOf(s)).length},
                  onChanged: (v) => setState(() => _storeTab = v),
                ),
              if (d.zones.isEmpty)
                const InfoBox(
                  title: 'Using Ikiguzi standard rates',
                  text: 'Until you add a zone, buyers pay Ikiguzi standard delivery: free in Kigali City and 5,000 RWF elsewhere (express 10,000 RWF). Add zones to set your own fees and coverage.',
                ),
              if (usingOther) const InfoBox(title: 'No zones for this store yet', text: "Checkout uses your other stores' zones for its items until you add zones here."),
              Section(
                title: 'Zones',
                subtitle: '${storeZones.length} zone${storeZones.length == 1 ? '' : 's'} for this store',
                children: [
                  if (storeZones.isEmpty) const Tiny('No zones yet. Add one for each area you deliver to, e.g. Kigali City and a nationwide fallback.'),
                  for (final z in storeZones)
                    RecordCard(
                      title: strOf(z['name']),
                      subtitle: strOf(z['coverage']),
                      lines: [
                        'Standard ${numOf(z['fee']) == 0 ? 'Free' : money(z['fee'])}'
                            '${(z['methods'] is List && (z['methods'] as List).contains('EXPRESS')) ? ' · Express ${money(z['expressFee'] ?? z['fee'])}' : ''}'
                            '${(z['methods'] is List && (z['methods'] as List).contains('PICKUP')) ? ' · Pickup ${numOf(z['pickupFee']) > 0 ? money(z['pickupFee']) : 'Free'}' : ''}',
                        '${numOf(z['freeOverAmount']) > 0 ? 'Free from ${money(z['freeOverAmount'])} · ' : ''}Time ${z['eta'] ?? ''}',
                      ],
                      status: Pill(z['status']),
                      actions: [
                        ActionChipBtn('Edit', icon: Icons.edit_outlined, onPressed: () => _edit(z, active)),
                        ActionChipBtn(
                          z['status'] == 'ACTIVE' ? 'Pause' : 'Activate',
                          onPressed: () async {
                            if (await runAction(context, () => jpatch('/shipping/zones/${z['id']}', {'status': z['status'] == 'ACTIVE' ? 'PAUSED' : 'ACTIVE'}), success: 'Zone updated.')) {
                              _data.reload();
                            }
                          },
                        ),
                        ActionChipBtn(
                          'Delete',
                          danger: true,
                          onPressed: () async {
                            if (!await confirmDialog(context, 'Delete zone ${z['name']}?', confirm: 'Delete', danger: true)) return;
                            if (context.mounted && await runAction(context, () => jdelete('/shipping/zones/${z['id']}'), success: 'Zone deleted.')) _data.reload();
                          },
                        ),
                      ],
                    ),
                ],
              ),
              Section(
                title: 'Coverage',
                subtitle: d.zones.isNotEmpty ? (uncovered > 0 ? '$uncovered of 30 districts not delivered' : 'All 30 districts delivered') : 'Ikiguzi standard rates apply',
                children: [
                  for (final p in rwandaLocations.keys) ...[
                    Padding(padding: const EdgeInsets.only(top: 6, bottom: 4), child: Text(p, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5))),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final dist in rwandaLocations[p]!)
                          Builder(
                            builder: (_) {
                              final z = _zoneFor(effective, p, dist);
                              final tone =
                                  d.zones.isEmpty
                                      ? StatusTone.neutral
                                      : z != null
                                      ? StatusTone.good
                                      : StatusTone.bad;
                              final fee = z == null ? '' : (numOf(z['fee']) == 0 ? ' · Free' : ' · ${(numOf(z['fee']) / 1000 * 10).round() / 10}k');
                              return StatusChip('$dist$fee', tone: tone);
                            },
                          ),
                      ],
                    ),
                  ],
                ],
              ),
              _PreviewCard(storeId: active),
            ],
          ],
        );
      },
    );
  }
}

class _PreviewCard extends StatefulWidget {
  const _PreviewCard({required this.storeId});
  final String storeId;

  @override
  State<_PreviewCard> createState() => _PreviewCardState();
}

class _PreviewCardState extends State<_PreviewCard> {
  String _province = 'Kigali City';
  String _district = 'Gasabo';
  String _method = 'STANDARD';
  final _subtotal = TextEditingController(text: '20000');
  Map<String, dynamic>? _result;
  String _error = '';
  bool _busy = false;

  @override
  void dispose() {
    _subtotal.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final r = await jpost('/shipping/preview', {
        'province': _province,
        'district': _district,
        'subtotal': numOf(_subtotal.text),
        'method': _method,
        if (widget.storeId.isNotEmpty) 'storeId': widget.storeId,
      });
      if (mounted) setState(() => _result = r);
    } catch (e) {
      if (mounted) {
        setState(() => _error = errorText(e));
        toast(context, errorText(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return Section(
      title: 'Test an address',
      subtitle: 'What a buyer pays for delivery from this store',
      children: [
        FilterSelect(
          label: 'Province',
          value: _province,
          options: [for (final p in rwandaLocations.keys) (p, p)],
          onChanged:
              (v) => setState(() {
                _province = v;
                _district = rwandaLocations[v]!.first;
              }),
        ),
        const SizedBox(height: 10),
        FilterSelect(label: 'District', value: _district, options: [for (final d in rwandaLocations[_province]!) (d, d)], onChanged: (v) => setState(() => _district = v)),
        const SizedBox(height: 10),
        TextField(controller: _subtotal, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Order subtotal (RWF)')),
        const SizedBox(height: 10),
        FilterSelect(label: 'Method', value: _method, options: const [('STANDARD', 'Standard'), ('EXPRESS', 'Express'), ('PICKUP', 'Pickup')], onChanged: (v) => setState(() => _method = v)),
        const SizedBox(height: 10),
        OutlineBtn(label: 'Check delivery', loading: _busy, onPressed: _test),
        const SizedBox(height: 10),
        if (_error.isNotEmpty) Notice(text: _error),
        if (r != null)
          r['deliverable'] == true
              ? Notice(
                ok: true,
                text: numOf(r['fee']) == 0 ? 'Free delivery' : money(r['fee']),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Tiny('${r['method'] != _method ? '${titleCase(_method)} not offered, ${titleCase(r['method']).toLowerCase()} used · ' : ''}${r['zoneName'] ?? ''} · ${r['eta'] ?? ''}'),
                    if (r['source'] != 'seller') const Tiny('You have no zones yet, so Ikiguzi standard rates apply.'),
                  ],
                ),
              )
              : Notice(text: 'Not delivered', child: Tiny("No active zone covers ${asMap(r['address'])['district'] ?? _district}. Buyers there can't order from this store.")),
      ],
    );
  }
}

class _ZoneEditor extends StatefulWidget {
  const _ZoneEditor({this.zone, required this.storeId});
  final Map<String, dynamic>? zone;
  final String storeId;

  @override
  State<_ZoneEditor> createState() => _ZoneEditorState();
}

class _ZoneEditorState extends State<_ZoneEditor> {
  late final _z = widget.zone ?? const <String, dynamic>{};
  late final _name = TextEditingController(text: strOf(_z['name']));
  late final _fee = TextEditingController(text: _z['fee'] == null ? '' : '${numOf(_z['fee'])}');
  late final _eta = TextEditingController(text: strOf(_z['eta'], widget.zone == null ? '1–3 days' : ''));
  late final _free = TextEditingController(text: numOf(_z['freeOverAmount']) > 0 ? '${numOf(_z['freeOverAmount'])}' : '');
  late final _expressFee = TextEditingController(text: _z['expressFee'] == null ? '' : '${numOf(_z['expressFee'])}');
  late final _pickupFee = TextEditingController(text: '${numOf(_z['pickupFee'])}');
  late String _scope =
      (_z['districts'] is List && (_z['districts'] as List).isNotEmpty)
          ? 'DISTRICTS'
          : (_z['provinces'] is List && (_z['provinces'] as List).isNotEmpty) || widget.zone == null
          ? 'PROVINCES'
          : 'ALL';
  late final Set<String> _provinces = {for (final p in (_z['provinces'] is List ? _z['provinces'] as List : const [])) '$p'};
  late final Set<String> _districts = {for (final d in (_z['districts'] is List ? _z['districts'] as List : const [])) '$d'};
  late bool _express = _z['methods'] is List && (_z['methods'] as List).contains('EXPRESS');
  late bool _pickup = _z['methods'] is List && (_z['methods'] as List).contains('PICKUP');
  late String _status = strOf(_z['status'], 'ACTIVE');
  bool _busy = false;
  String _error = '';

  @override
  void dispose() {
    for (final c in [_name, _fee, _eta, _free, _expressFee, _pickupFee]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _error = '');
    if (_name.text.trim().isEmpty || _fee.text.trim().isEmpty) return setState(() => _error = 'Enter the zone name and the standard fee.');
    if (_scope == 'PROVINCES' && _provinces.isEmpty) return setState(() => _error = 'Select at least one province.');
    if (_scope == 'DISTRICTS' && _districts.isEmpty) return setState(() => _error = 'Select at least one district.');
    if (_express && _expressFee.text.isNotEmpty && numOf(_expressFee.text) < numOf(_fee.text)) return setState(() => _error = 'Express delivery should not cost less than standard.');
    final payload = {
      'name': _name.text.trim(),
      'provinces': _scope == 'PROVINCES' ? _provinces.toList() : <String>[],
      'districts': _scope == 'DISTRICTS' ? _districts.toList() : <String>[],
      'fee': numOf(_fee.text),
      'expressFee': _express && _expressFee.text.isNotEmpty ? numOf(_expressFee.text) : null,
      'pickupFee': _pickup ? numOf(_pickupFee.text) : 0,
      'methods': ['STANDARD', if (_express) 'EXPRESS', if (_pickup) 'PICKUP'],
      'freeOverAmount': numOf(_free.text),
      'eta': _eta.text.trim().isEmpty ? '1–3 days' : _eta.text.trim(),
      'status': _status,
      if (widget.zone == null && widget.storeId.isNotEmpty) 'storeId': widget.storeId,
    };
    setState(() => _busy = true);
    try {
      if (widget.zone == null) {
        await jpost('/shipping/zones', payload);
      } else {
        await jpatch('/shipping/zones/${widget.zone!['id']}', payload);
      }
      if (mounted) Navigator.of(context).pop(widget.zone == null ? 'Shipping zone added.' : 'Shipping zone saved.');
    } catch (e) {
      if (mounted) {
        setState(() => _error = errorText(e));
        toast(context, errorText(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget check(String label, bool on, VoidCallback tap) =>
        CheckboxListTile(dense: true, contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading, value: on, title: Text(label), onChanged: (_) => tap());
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close_rounded), tooltip: 'Cancel', onPressed: () => Navigator.of(context).pop()),
        title: Text(widget.zone == null ? 'Add shipping zone' : 'Edit shipping zone'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          children: [
            const Tiny('Buyers in these areas pay these fees for items from this store.'),
            if (_error.isNotEmpty) Notice(text: _error),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Zone name *', hintText: 'e.g. Kigali City')),
            const SizedBox(height: 14),
            const Text('Where you deliver', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'ALL', label: Text('All Rwanda')),
                ButtonSegment(value: 'PROVINCES', label: Text('Provinces')),
                ButtonSegment(value: 'DISTRICTS', label: Text('Districts')),
              ],
              selected: {_scope},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _scope = s.first),
            ),
            if (_scope == 'ALL') const Tiny('Used for any address not covered by a more specific province or district zone.'),
            if (_scope == 'PROVINCES')
              for (final p in rwandaLocations.keys) check(p, _provinces.contains(p), () => setState(() => _provinces.contains(p) ? _provinces.remove(p) : _provinces.add(p))),
            if (_scope == 'DISTRICTS')
              for (final p in rwandaLocations.keys)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text('$p  ${rwandaLocations[p]!.where(_districts.contains).length}/${rwandaLocations[p]!.length}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  children: [
                    check(
                      'All of $p',
                      rwandaLocations[p]!.every(_districts.contains),
                      () => setState(() {
                        final all = rwandaLocations[p]!;
                        all.every(_districts.contains) ? _districts.removeAll(all) : _districts.addAll(all);
                      }),
                    ),
                    for (final dist in rwandaLocations[p]!) check(dist, _districts.contains(dist), () => setState(() => _districts.contains(dist) ? _districts.remove(dist) : _districts.add(dist))),
                  ],
                ),
            const SizedBox(height: 14),
            const Text('Fees', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            TextField(controller: _fee, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Standard fee (RWF) *')),
            const SizedBox(height: 10),
            TextField(controller: _eta, decoration: const InputDecoration(labelText: 'Delivery time', hintText: '1–3 days')),
            const SizedBox(height: 10),
            TextField(
              controller: _free,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Free standard delivery from (RWF)', hintText: 'No free delivery', helperText: 'Order subtotal from this store.'),
            ),
            const SizedBox(height: 10),
            FilterSelect(label: 'Status', value: _status, options: const [('ACTIVE', 'Active'), ('PAUSED', 'Paused')], onChanged: (v) => setState(() => _status = v)),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Offer express delivery'), value: _express, onChanged: (v) => setState(() => _express = v)),
            if (_express) TextField(controller: _expressFee, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Express fee (RWF)', hintText: 'Same as standard')),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Allow pickup'), value: _pickup, onChanged: (v) => setState(() => _pickup = v)),
            if (_pickup) TextField(controller: _pickupFee, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Pickup fee (RWF)')),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 10), child: GradientButton(label: widget.zone == null ? 'Add zone' : 'Save changes', loading: _busy, onPressed: _save)),
      ),
    );
  }
}

// ─── Reviews ─────────────────────────────────────────────────────────────────
