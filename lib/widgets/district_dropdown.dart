import 'package:flutter/material.dart';

import '../core/locations.dart';

/// One of Rwanda's 30 districts, listed under their province.
class DistrictDropdown extends StatelessWidget {
  const DistrictDropdown({super.key, required this.value, required this.onChanged, this.label = 'District', this.enabled = true});

  final String value;
  final ValueChanged<String> onChanged;
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: '', child: Text('Choose a district')),
      for (final p in provinces) ...[
        DropdownMenuItem(enabled: false, value: '#$p', child: Text(p, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Theme.of(context).hintColor))),
        for (final d in rwandaLocations[p]!) DropdownMenuItem(value: d, child: Padding(padding: const EdgeInsets.only(left: 12), child: Text(d))),
      ],
    ];
    final known = rwandaLocations.values.any((ds) => ds.contains(value));
    return DropdownButtonFormField<String>(
      initialValue: known ? value : '',
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: items,
      onChanged: enabled ? (v) => onChanged(v == null || v.startsWith('#') ? '' : v) : null,
    );
  }
}

/// Several of Rwanda's districts (a rider's work area): chips for the chosen
/// ones, and a list to add more.
class DistrictsPicker extends StatelessWidget {
  const DistrictsPicker({super.key, required this.value, required this.onChanged, this.label = 'Districts you deliver in', this.enabled = true});

  final List<String> value;
  final ValueChanged<List<String>> onChanged;
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final items = <DropdownMenuItem<String>>[
      DropdownMenuItem(value: '', child: Text(value.isEmpty ? 'Choose a district' : 'Add another district')),
      for (final p in provinces) ...[
        DropdownMenuItem(enabled: false, value: '#$p', child: Text(p, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Theme.of(context).hintColor))),
        for (final d in rwandaLocations[p]!.where((d) => !value.contains(d))) DropdownMenuItem(value: d, child: Padding(padding: const EdgeInsets.only(left: 12), child: Text(d))),
      ],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (value.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final d in value)
                InputChip(
                  label: Text(d),
                  onDeleted: enabled ? () => onChanged([...value]..remove(d)) : null,
                  deleteButtonTooltipMessage: 'Remove $d',
                  visualDensity: VisualDensity.compact,
                ),
            ]),
          ),
        DropdownButtonFormField<String>(
          key: ValueKey(value.join('|')),
          initialValue: '',
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: items,
          onChanged: enabled ? (v) { if (v != null && v.isNotEmpty && !v.startsWith('#')) onChanged([...value, v]); } : null,
        ),
      ],
    );
  }
}
