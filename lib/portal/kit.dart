import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../core/upload.dart';
import '../widgets/common.dart';

// Building blocks shared by every dashboard (seller, supplier, affiliate,
// courier, admin). They mirror the web's seller/shared.jsx helpers:
// `useLoader`, `FormModal`, `StatusPill`, `Metric`, tabs and toolbars.

/// "Delivered" style label for any backend status (`titleCase` on the web).
String titleCase(dynamic s) => statusLabel(s);

/// `personName()` on the web: populated users come as `{Fullname}`.
String personName(dynamic u, [String fallback = 'Buyer']) {
  if (u is! Map) return fallback;
  return strOf(u['fullName'] ?? u['Fullname'] ?? u['name'] ?? u['companyName'], fallback);
}

/// Matches the search box on the given fields only (`matches()` on the web).
bool matches(String q, List<dynamic> fields) {
  final term = q.trim().toLowerCase();
  if (term.isEmpty) return true;
  return fields.any((f) => '${f ?? ''}'.toLowerCase().contains(term));
}

/// Loads data for a page and keeps loading / error / data state, with reload.
/// Pages keep one of these and rebuild through [LoadView].
class Loader<T> extends ChangeNotifier {
  Loader(this._load, {bool auto = true}) {
    if (auto) reload();
  }

  final Future<T> Function() _load;
  T? data;
  Object? error;
  bool loading = true;
  bool _disposed = false;

  Future<void> reload() async {
    loading = true;
    error = null;
    _notify();
    try {
      final v = await _load();
      data = v;
      error = null;
    } catch (e) {
      error = e;
    } finally {
      loading = false;
      _notify();
    }
  }

  void set(T value) {
    data = value;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Scrolling dashboard page with pull-to-refresh and the page heading.
class PortalPage extends StatelessWidget {
  const PortalPage({super.key, required this.title, this.eyebrow, this.subtitle, this.action, this.onRefresh, required this.children});

  final String title;
  final String? eyebrow;
  final String? subtitle;
  final Widget? action;
  final Future<void> Function()? onRefresh;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [PageTitle(eyebrow: eyebrow, title: title, subtitle: subtitle), if (action != null) Padding(padding: const EdgeInsets.only(bottom: 14), child: action!), ...children],
    );
    return onRefresh == null ? list : RefreshIndicator(onRefresh: onRefresh!, child: list);
  }
}

/// Shows a [Loader]'s loading / error state, or [builder] once data is in.
class LoadView<T> extends StatelessWidget {
  const LoadView({super.key, required this.loader, required this.builder, this.loadingLabel, this.page = false});
  final Loader<T> loader;
  final Widget Function(T data) builder;
  final String? loadingLabel;

  /// [builder] returns a whole scrolling page (a [PortalPage]): it is shown as
  /// is, filling the screen, instead of inside a column.
  final bool page;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: loader,
      builder: (context, _) {
        final data = loader.data;
        if (data == null) {
          if (loader.error != null) return ErrorState(error: loader.error!, onRetry: loader.reload);
          return LoadingState(label: loadingLabel);
        }
        if (page) return builder(data);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [if (loader.error != null) Notice(text: errorText(loader.error!)), builder(data)]);
      },
    );
  }
}

/// A row of selectable chips with counts (`.seller-view-tabs`).
class TabChips extends StatelessWidget {
  const TabChips({super.key, required this.tabs, required this.value, required this.onChanged, this.counts});
  final List<(String, String)> tabs;
  final String value;
  final ValueChanged<String> onChanged;
  final Map<String, int>? counts;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (key, label) in tabs)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(showCheckmark: false, selected: value == key, onSelected: (_) => onChanged(key), label: Text(counts?[key] == null ? label : '$label  ${counts![key]}')),
              ),
          ],
        ),
      ),
    );
  }
}

/// Search box (`.dash-filter`).
class SearchBox extends StatefulWidget {
  const SearchBox({super.key, required this.onChanged, this.hint = 'Search', this.initial = ''});
  final ValueChanged<String> onChanged;
  final String hint;
  final String initial;

  @override
  State<SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<SearchBox> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _c,
        onChanged: (v) {
          widget.onChanged(v);
          setState(() {});
        },
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: widget.hint,
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          isDense: true,
          suffixIcon:
              _c.text.isEmpty
                  ? null
                  : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () {
                      _c.clear();
                      widget.onChanged('');
                      setState(() {});
                    },
                  ),
        ),
      ),
    );
  }
}

/// Compact dropdown used as a filter (`.table-filter-select`).
class FilterSelect extends StatelessWidget {
  const FilterSelect({super.key, required this.value, required this.options, required this.onChanged, this.label});
  final String value;
  final List<(String, String)> options;
  final ValueChanged<String> onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final safe = options.any((o) => o.$1 == value) ? value : (options.isEmpty ? null : options.first.$1);
    return DropdownButtonFormField<String>(
      initialValue: safe,
      isExpanded: true,
      isDense: true,
      decoration: InputDecoration(labelText: label, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
      items: [for (final (v, l) in options) DropdownMenuItem(value: v, child: Text(l, overflow: TextOverflow.ellipsis))],
      onChanged: (v) => onChanged(v ?? ''),
    );
  }
}

/// Lays filters side by side, wrapping on narrow phones.
class FilterRow extends StatelessWidget {
  const FilterRow({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LayoutBuilder(
        builder: (context, c) {
          final cols = c.maxWidth < 340 ? 1 : 2;
          final w = (c.maxWidth - (cols - 1) * 10) / cols;
          return Wrap(spacing: 10, runSpacing: 10, children: [for (final f in children) SizedBox(width: w, child: f)]);
        },
      ),
    );
  }
}

/// Status pill with the web's tone rules (`StatusPill`).
class Pill extends StatelessWidget {
  const Pill(this.value, {super.key, this.label});
  final dynamic value;
  final String? label;

  static const _good = {
    'ACTIVE',
    'PAID',
    'DELIVERED',
    'COMPLETED',
    'PUBLISHED',
    'VERIFIED',
    'RELEASED',
    'OWNER',
    'APPROVED',
    'SUCCESS',
    'SUCCESSFUL',
    'RESOLVED',
    'ACCEPTED',
    'LIVE',
    'IN_STOCK',
    'CONFIRMED_RECEIPT',
  };
  static const _bad = {'CANCELLED', 'FAILED', 'REJECTED', 'SUSPENDED', 'EXPIRED', 'REFUNDED', 'BLOCKED', 'DISPUTED', 'BANNED', 'OUT_OF_STOCK', 'DECLINED', 'TERMINATED'};

  @override
  Widget build(BuildContext context) {
    final key = '${value ?? ''}'.toUpperCase().replaceAll(RegExp(r'\s+'), '_');
    final tone =
        _good.contains(key) || key.startsWith('RESOLVED')
            ? StatusTone.good
            : _bad.contains(key)
            ? StatusTone.bad
            : StatusTone.warn;
    return StatusChip(label ?? titleCase(value), tone: tone);
  }
}

/// A record in a list (`.activity-row` / table row on the web).
class RecordCard extends StatelessWidget {
  const RecordCard({
    super.key,
    required this.title,
    this.subtitle,
    this.lines = const [],
    this.amount,
    this.status,
    this.leading,
    this.onTap,
    this.actions = const [],
    this.badges = const [],
    this.selected = false,
  });

  final String title;
  final String? subtitle;
  final List<String> lines;
  final String? amount;
  final Widget? status;
  final Widget? leading;
  final VoidCallback? onTap;
  final List<Widget> actions;
  final List<Widget> badges;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    final card = Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: selected ? mv.soft : mv.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: selected ? MvColors.skyBlue : mv.border)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (leading != null) ...[leading!, const SizedBox(width: 10)],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: mv.text, fontSize: 14)), ...badges],
                        ),
                        if (subtitle != null && subtitle!.isNotEmpty) ...[const SizedBox(height: 2), Text(subtitle!, style: TextStyle(color: mv.textMuted, fontSize: 12.5))],
                        for (final l in lines.where((l) => l.trim().isNotEmpty)) Padding(padding: const EdgeInsets.only(top: 2), child: Text(l, style: TextStyle(color: mv.textMuted, fontSize: 12))),
                      ],
                    ),
                  ),
                  if (amount != null || status != null) ...[
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (amount != null) Text(amount!, style: TextStyle(fontWeight: FontWeight.w800, color: mv.text, fontSize: 13.5)),
                        if (amount != null && status != null) const SizedBox(height: 4),
                        if (status != null) status!,
                      ],
                    ),
                  ],
                  if (onTap != null && actions.isEmpty) Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.chevron_right_rounded, color: mv.textMuted, size: 20)),
                ],
              ),
              if (actions.isNotEmpty) ...[const SizedBox(height: 10), Wrap(spacing: 8, runSpacing: 8, children: actions)],
            ],
          ),
        ),
      ),
    );
    return Semantics(container: true, child: card);
  }
}

/// Small button used inside record cards (`.table-action-btn`).
class ActionChipBtn extends StatelessWidget {
  const ActionChipBtn(this.label, {super.key, required this.onPressed, this.primary = false, this.danger = false, this.icon, this.busy = false});
  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final bool danger;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    final fg =
        danger
            ? MvColors.errorText
            : primary
            ? Colors.white
            : mv.accentDeep;
    final bg = primary ? MvColors.primaryDark : mv.surface;
    final button = Material(
      color: onPressed == null ? bg.withValues(alpha: .5) : bg,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: busy ? null : onPressed,
        child: Container(
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(9), border: Border.all(color: primary ? Colors.transparent : (danger ? MvColors.errorText.withValues(alpha: .35) : mv.border))),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy) SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: fg)) else if (icon != null) Icon(icon, size: 16, color: fg),
              if (busy || icon != null) const SizedBox(width: 6),
              Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12.5)),
            ],
          ),
        ),
      ),
    );
    return Semantics(container: true, button: true, enabled: onPressed != null && !busy, child: button);
  }
}

/// Label / value line in a detail card.
class KV extends StatelessWidget {
  const KV(this.label, this.value, {super.key, this.bold = false});
  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) => SummaryRow(label, value.isEmpty ? '—' : value, bold: bold);
}

/// Card with a heading row (`.data-card` + `.data-card-head`).
class Section extends StatelessWidget {
  const Section({super.key, required this.title, this.subtitle, this.trailing, required this.children});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    return DataCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700, color: mv.text)),
                    if (subtitle != null && subtitle!.isNotEmpty) Text(subtitle!, style: TextStyle(color: mv.textMuted, fontSize: 12)),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

/// Small grey note (`.tiny`).
class Tiny extends StatelessWidget {
  const Tiny(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(text, style: TextStyle(color: color ?? context.mv.textMuted, fontSize: 12, height: 1.4)));
}

/// Bar chart of labelled values (`BarChart` in seller/shared.jsx).
class MiniBars extends StatelessWidget {
  const MiniBars({super.key, required this.data, this.format = money, this.height = 140});
  final List<(String, num)> data;
  final String Function(dynamic) format;
  final double height;

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    final maxV = data.fold<num>(1, (m, d) => d.$2 > m ? d.$2 : m);
    return SizedBox(
      height: height + 34,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (label, v) in data)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (v > 0) FittedBox(child: Text(compact(v), style: TextStyle(fontSize: 9.5, color: mv.textMuted))),
                    const SizedBox(height: 2),
                    Container(height: (v / maxV) * height + 2, decoration: BoxDecoration(gradient: MvColors.gradient, borderRadius: BorderRadius.circular(5))),
                    const SizedBox(height: 4),
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: mv.textMuted)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Paginates a list client-side and draws the pager (`Pagination.jsx`).
class Paged<T> extends StatefulWidget {
  const Paged({super.key, required this.items, required this.itemBuilder, this.perPage = 10, this.empty});
  final List<T> items;
  final Widget Function(T item) itemBuilder;
  final int perPage;
  final Widget? empty;

  @override
  State<Paged<T>> createState() => _PagedState<T>();
}

class _PagedState<T> extends State<Paged<T>> {
  int _page = 1;

  @override
  void didUpdateWidget(covariant Paged<T> old) {
    super.didUpdateWidget(old);
    final pages = (widget.items.length / widget.perPage).ceil().clamp(1, 1 << 30);
    if (_page > pages) _page = pages;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return widget.empty ?? const SizedBox.shrink();
    final start = (_page - 1) * widget.perPage;
    final shown = widget.items.skip(start).take(widget.perPage);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final i in shown) widget.itemBuilder(i), PaginationBar(page: _page, total: widget.items.length, perPage: widget.perPage, onPage: (p) => setState(() => _page = p))],
    );
  }
}

// ─── Forms ───────────────────────────────────────────────────────────────────

enum FieldType { text, number, email, phone, password, textarea, select, checkboxes, toggle, date, image }

/// One input in a [FormSheet] (the web `FormModal` field config).
class FieldSpec {
  const FieldSpec(this.name, this.label, {this.type = FieldType.text, this.options = const [], this.required = false, this.hint, this.help, this.placeholderOption, this.lines = 3, this.visibleWhen});

  final String name;
  final String label;
  final FieldType type;
  final List<(String, String)> options;
  final bool required;
  final String? hint;
  final String? help;

  /// First "empty" option for selects (e.g. "None (top-level category)").
  final String? placeholderOption;
  final int lines;

  /// Shown only when this returns true for the current values.
  final bool Function(Map<String, dynamic> values)? visibleWhen;
}

/// Opens a bottom-sheet form. [onSubmit] runs with the values; when it throws,
/// the message is shown in the sheet and the sheet stays open. Returns the
/// value [onSubmit] returned, or null when the person closed the sheet.
Future<R?> showFormSheet<R>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<FieldSpec> fields,
  Map<String, dynamic> initial = const {},
  String submitLabel = 'Save',
  bool danger = false,
  required Future<R> Function(Map<String, dynamic> values) onSubmit,
  Map<String, dynamic>? Function(String name, dynamic value, Map<String, dynamic> values)? onFieldChange,
  List<FieldSpec> Function(Map<String, dynamic> values)? fieldsFor,
}) {
  return showModalBottomSheet<R>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder:
        (_) => _FormSheet<R>(
          title: title,
          subtitle: subtitle,
          fields: fields,
          fieldsFor: fieldsFor,
          initial: initial,
          submitLabel: submitLabel,
          danger: danger,
          onSubmit: onSubmit,
          onFieldChange: onFieldChange,
        ),
  );
}

class _FormSheet<R> extends StatefulWidget {
  const _FormSheet({
    required this.title,
    this.subtitle,
    required this.fields,
    this.fieldsFor,
    required this.initial,
    required this.submitLabel,
    required this.danger,
    required this.onSubmit,
    this.onFieldChange,
  });

  final String title;
  final String? subtitle;
  final List<FieldSpec> fields;
  final List<FieldSpec> Function(Map<String, dynamic>)? fieldsFor;
  final Map<String, dynamic> initial;
  final String submitLabel;
  final bool danger;
  final Future<R> Function(Map<String, dynamic>) onSubmit;
  final Map<String, dynamic>? Function(String, dynamic, Map<String, dynamic>)? onFieldChange;

  @override
  State<_FormSheet<R>> createState() => _FormSheetState<R>();
}

class _FormSheetState<R> extends State<_FormSheet<R>> {
  late final Map<String, dynamic> _v = {...widget.initial};
  final Map<String, TextEditingController> _c = {};
  bool _busy = false;
  String _error = '';
  String _uploading = '';

  TextEditingController _ctl(String name) => _c.putIfAbsent(name, () => TextEditingController(text: '${_v[name] ?? ''}'));

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _set(String name, dynamic value) {
    final patch = widget.onFieldChange?.call(name, value, {..._v, name: value});
    setState(() {
      _v[name] = value;
      if (patch != null) {
        _v.addAll(patch);
        for (final e in patch.entries) {
          if (_c.containsKey(e.key)) _c[e.key]!.text = '${e.value ?? ''}';
        }
      }
    });
  }

  List<FieldSpec> get _fields => (widget.fieldsFor?.call(_v) ?? widget.fields).where((f) => f.visibleWhen?.call(_v) ?? true).toList();

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    for (final f in _fields) {
      final v = _v[f.name];
      final empty = v == null || (v is String && v.trim().isEmpty) || (v is List && v.isEmpty);
      if (f.required && empty) {
        setState(() => _error = '${f.label} is required.');
        return;
      }
      if (f.type == FieldType.email && v is String && v.trim().isNotEmpty && !isEmail(v)) {
        setState(() => _error = 'Enter a valid email address.');
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final r = await widget.onSubmit({..._v});
      if (mounted) Navigator.of(context).pop(r);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = errorText(e);
        });
      }
    }
  }

  Widget _field(FieldSpec f) {
    final mv = context.mv;
    final label = '${f.label}${f.required ? ' *' : ''}';
    switch (f.type) {
      case FieldType.select:
        final opts = [if (f.placeholderOption != null) ('', f.placeholderOption!), ...f.options];
        final cur = '${_v[f.name] ?? ''}';
        return DropdownButtonFormField<String>(
          initialValue: opts.any((o) => o.$1 == cur) ? cur : (opts.isEmpty ? null : opts.first.$1),
          isExpanded: true,
          decoration: InputDecoration(labelText: label, helperText: f.help, helperMaxLines: 3),
          items: [for (final (v, l) in opts) DropdownMenuItem(value: v, child: Text(l, overflow: TextOverflow.ellipsis))],
          onChanged: (v) => _set(f.name, v ?? ''),
        );
      case FieldType.checkboxes:
        final list = (_v[f.name] is List ? List<String>.from(_v[f.name] as List) : <String>[]);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: mv.textMuted, fontSize: 12.5, fontWeight: FontWeight.w600)),
            for (final (v, l) in f.options)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: list.contains(v),
                title: Text(l, style: const TextStyle(fontSize: 13.5)),
                onChanged: (on) => _set(f.name, on == true ? [...list, v] : list.where((x) => x != v).toList()),
              ),
            if (f.help != null) Tiny(f.help!),
          ],
        );
      case FieldType.toggle:
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _v[f.name] == true,
          title: Text(f.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          subtitle: f.help == null ? null : Text(f.help!, style: const TextStyle(fontSize: 12)),
          onChanged: (on) => _set(f.name, on),
        );
      case FieldType.image:
        final url = '${_v[f.name] ?? ''}';
        return Row(
          children: [
            ProductImage(src: url, size: 64, radius: 10),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(color: mv.textMuted, fontSize: 12.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  ActionChipBtn(
                    url.isEmpty ? 'Upload image' : 'Change image',
                    icon: Icons.upload_rounded,
                    busy: _uploading == f.name,
                    onPressed: () async {
                      setState(() => _uploading = f.name);
                      try {
                        final urls = await pickAndUploadImages(multiple: false);
                        if (urls.isNotEmpty) _set(f.name, urls.first);
                      } catch (e) {
                        if (mounted) {
                          setState(() => _error = errorText(e));
                          toast(context, errorText(e), error: true);
                        }
                      } finally {
                        if (mounted) setState(() => _uploading = '');
                      }
                    },
                  ),
                  if (f.help != null) Tiny(f.help!),
                ],
              ),
            ),
          ],
        );
      case FieldType.date:
        final cur = '${_v[f.name] ?? ''}';
        return InkWell(
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(context: context, initialDate: DateTime.tryParse(cur) ?? now, firstDate: DateTime(now.year - 5), lastDate: DateTime(now.year + 5));
            if (picked != null) _set(f.name, picked.toIso8601String().substring(0, 10));
          },
          child: InputDecorator(
            decoration: InputDecoration(labelText: label, helperText: f.help, suffixIcon: const Icon(Icons.event_outlined, size: 20)),
            child: Text(cur.isEmpty ? (f.hint ?? 'Choose a date') : formatDate(cur), style: TextStyle(color: cur.isEmpty ? mv.textMuted : mv.text)),
          ),
        );
      default:
        final number = f.type == FieldType.number;
        return TextField(
          controller: _ctl(f.name),
          obscureText: f.type == FieldType.password,
          minLines: f.type == FieldType.textarea ? 2 : 1,
          maxLines: f.type == FieldType.textarea ? f.lines + 2 : 1,
          keyboardType:
              number
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : f.type == FieldType.email
                  ? TextInputType.emailAddress
                  : f.type == FieldType.phone
                  ? TextInputType.phone
                  : f.type == FieldType.textarea
                  ? TextInputType.multiline
                  : TextInputType.text,
          inputFormatters: number ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))] : null,
          decoration: InputDecoration(labelText: label, hintText: f.hint, helperText: f.help, helperMaxLines: 3),
          onChanged: (v) {
            final patch = widget.onFieldChange?.call(f.name, v, {..._v, f.name: v});
            _v[f.name] = v;
            if (patch != null) setState(() => _v.addAll(patch));
          },
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w700, color: mv.text)),
            if (widget.subtitle != null) ...[const SizedBox(height: 4), Text(widget.subtitle!, style: TextStyle(color: mv.textMuted, fontSize: 13, height: 1.4))],
            const SizedBox(height: 14),
            if (_error.isNotEmpty) Notice(text: _error),
            for (final f in _fields) Padding(padding: const EdgeInsets.only(bottom: 12), child: _field(f)),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(child: OutlineBtn(label: 'Cancel', onPressed: _busy || _uploading.isNotEmpty ? null : () => Navigator.of(context).pop())),
                const SizedBox(width: 10),
                Expanded(
                  child:
                      widget.danger
                          ? SolidButton(label: widget.submitLabel, color: MvColors.dangerBtn, loading: _busy, onPressed: _submit)
                          : GradientButton(label: widget.submitLabel, loading: _busy, onPressed: _uploading.isNotEmpty ? null : _submit),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Runs an action, shows its success message (or the error) as a toast and
/// returns whether it worked.
Future<bool> runAction(BuildContext context, Future<dynamic> Function() action, {String? success}) async {
  try {
    final res = await action();
    if (context.mounted) {
      final msg = success ?? (res is Map && res['message'] is String ? res['message'] as String : null);
      if (msg != null && msg.isNotEmpty) toast(context, msg);
    }
    return true;
  } catch (e) {
    if (context.mounted) toast(context, errorText(e), error: true);
    return false;
  }
}

/// Picks images from the gallery and uploads them (`uploadsApi.uploadImages`).
/// Returns the uploaded URLs (empty when the person cancelled).
Future<List<String>> pickAndUploadImages({bool multiple = true}) async {
  final picker = ImagePicker();
  final files = multiple ? await picker.pickMultiImage(maxWidth: 1600, imageQuality: 85) : [if (await picker.pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85) case final f?) f];
  if (files.isEmpty) return const [];
  final form = FormData();
  for (final f in files) {
    form.files.add(MapEntry('images', await imagePart(f)));
  }
  final res = asMap(await Api.instance.upload('/uploads/images', form));
  return [for (final u in (res['urls'] is List ? res['urls'] as List : const [])) '$u'];
}

/// Copies text and confirms with a toast.
Future<void> copyText(BuildContext context, String text, [String what = 'Copied']) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) toast(context, what);
}
