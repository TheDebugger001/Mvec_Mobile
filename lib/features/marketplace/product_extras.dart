import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/catalog_api.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../models/product.dart';
import '../../widgets/common.dart';

/// "2h 05m 09s" until [to], "" once it has passed.
String countdownText(DateTime? to, DateTime now) {
  if (to == null) return '';
  final left = to.difference(now);
  if (left.isNegative || left == Duration.zero) return '';
  final d = left.inDays;
  final h = left.inHours % 24;
  final m = (left.inMinutes % 60).toString().padLeft(2, '0');
  final s = (left.inSeconds % 60).toString().padLeft(2, '0');
  return d > 0 ? '${d}d ${h}h ${m}m' : '${h}h ${m}m ${s}s';
}

/// "Flash deal −30% · ends in 2h 05m" (or "starts in …"), ticking every second.
class DealTag extends StatefulWidget {
  const DealTag({super.key, required this.deal, this.compact = false});
  final Deal deal;
  final bool compact;

  @override
  State<DealTag> createState() => _DealTagState();
}

class _DealTagState extends State<DealTag> {
  Timer? _t;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _now = DateTime.now()));
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    final d = widget.deal;
    final left = countdownText(d.live ? d.endsAt : d.startsAt, _now);
    if (left.isEmpty) return const SizedBox.shrink();
    final head = d.live ? 'Flash deal −${d.percentOff}%' : 'Deal −${d.percentOff}% soon';
    final tail = '${d.live ? 'ends in' : 'starts in'} $left${d.left != null && !widget.compact ? ' · ${d.left} left' : ''}';
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 6),
      padding: EdgeInsets.symmetric(horizontal: widget.compact ? 8 : 10, vertical: widget.compact ? 2 : 5),
      decoration: BoxDecoration(color: d.live ? mv.soft : MvColors.warningBg, borderRadius: BorderRadius.circular(999)),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: '$head ', style: TextStyle(fontWeight: FontWeight.w800, color: d.live ? mv.accentDeep : MvColors.warningText)),
          TextSpan(text: tail, style: TextStyle(color: d.live ? mv.accentDeep : MvColors.warningText)),
        ]),
        style: TextStyle(fontSize: widget.compact ? 11 : 12.5),
        maxLines: widget.compact ? 1 : 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Earned seller badges (Verified, Top rated, Ships fast, New seller).
class SellerBadgeRow extends StatelessWidget {
  const SellerBadgeRow({super.key, required this.badges});
  final List<({String code, String label, String hint})> badges;

  @override
  Widget build(BuildContext context) {
    if (badges.isEmpty) return const SizedBox.shrink();
    final mv = context.mv;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(spacing: 6, runSpacing: 4, children: [
        for (final b in badges)
          Tooltip(
            message: b.hint,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: b.code == 'VERIFIED' ? mv.soft : mv.surface,
                border: Border.all(color: b.code == 'VERIFIED' ? mv.accent : mv.border),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('${b.code == 'VERIFIED' ? '✓ ' : ''}${b.label}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: b.code == 'VERIFIED' ? mv.accentDeep : mv.text)),
            ),
          ),
      ]),
    );
  }
}

/// One choice per option (Color, Size…); values with nothing in stock are faded.
class VariantPicker extends StatefulWidget {
  const VariantPicker({super.key, required this.product, required this.onChanged});
  final Product product;
  final ValueChanged<ProductVariant?> onChanged;

  @override
  State<VariantPicker> createState() => _VariantPickerState();
}

class _VariantPickerState extends State<VariantPicker> {
  final Map<String, String> _chosen = {};

  ProductVariant? _match() {
    final opts = widget.product.variantOptions;
    for (final v in widget.product.variants) {
      if (opts.every((o) => _chosen[o.name] != null && v.options[o.name] == _chosen[o.name])) return v;
    }
    return null;
  }

  bool _possible(String name, String value) => widget.product.variants.any((v) =>
      v.options[name] == value &&
      v.stock > 0 &&
      widget.product.variantOptions.every((o) => o.name == name || _chosen[o.name] == null || v.options[o.name] == _chosen[o.name]));

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final o in widget.product.variantOptions) ...[
          const SizedBox(height: 10),
          Text(_chosen[o.name] == null ? o.name : '${o.name}: ${_chosen[o.name]}', style: TextStyle(color: mv.textMuted, fontSize: 12)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final value in o.values)
              ChoiceChip(
                label: Text(value, style: TextStyle(decoration: _possible(o.name, value) ? null : TextDecoration.lineThrough)),
                selected: _chosen[o.name] == value,
                onSelected: (_) {
                  setState(() {
                    if (_chosen[o.name] == value) {
                      _chosen.remove(o.name);
                    } else {
                      _chosen[o.name] = value;
                    }
                  });
                  widget.onChanged(_match());
                },
              ),
          ]),
        ],
      ],
    );
  }
}

/// "Tell me when it's back" (sold out) and "Tell me if the price drops".
class StockAlertButtons extends StatefulWidget {
  const StockAlertButtons({super.key, required this.productId, required this.soldOut, required this.signedIn, required this.onSignIn});
  final String productId;
  final bool soldOut;
  final bool signedIn;
  final VoidCallback onSignIn;

  @override
  State<StockAlertButtons> createState() => _StockAlertButtonsState();
}

class _StockAlertButtonsState extends State<StockAlertButtons> {
  Map<String, bool> _on = const {};
  String _note = '';

  @override
  void initState() {
    super.initState();
    if (widget.signedIn) CatalogApi.alertsOn(widget.productId).then((v) { if (mounted) setState(() => _on = v); }).catchError((_) {});
  }

  Future<void> _toggle(String kind) async {
    if (!widget.signedIn) return widget.onSignIn();
    final on = _on[kind] == true;
    try {
      if (on) {
        await CatalogApi.unwatch(widget.productId, kind);
        _note = 'Alert removed.';
      } else {
        _note = await CatalogApi.watch(widget.productId, kind);
      }
      setState(() => _on = {..._on, kind: !on});
    } catch (e) {
      setState(() => _note = errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (widget.soldOut)
          OutlineBtn(label: _on['BACK_IN_STOCK'] == true ? "We'll tell you when it's back" : "Tell me when it's back", icon: Icons.notifications_active_outlined, compact: true, onPressed: () => _toggle('BACK_IN_STOCK')),
        OutlineBtn(label: _on['PRICE_DROP'] == true ? 'Watching the price' : 'Tell me if the price drops', icon: Icons.trending_down_rounded, compact: true, onPressed: () => _toggle('PRICE_DROP')),
      ]),
      if (_note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_note, style: TextStyle(color: context.mv.textMuted, fontSize: 12))),
    ]);
  }
}
