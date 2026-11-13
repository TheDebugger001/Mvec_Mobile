import 'dart:convert';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../widgets/common.dart';

const _bulkColumns = ['name', 'description', 'price', 'discountPrice', 'stockQuantity', 'category', 'brand', 'mainImage', 'status'];

const bulkTemplate =
    'name,description,price,discountPrice,stockQuantity,category,brand,mainImage,status\n'
    '"Wireless earbuds","Bluetooth 5.3 earbuds with charging case",25000,22000,40,Electronics,SoundMax,https://example.com/earbuds.jpg,DRAFT\n';

/// Minimal CSV reader: commas, quoted fields with "" escapes, CRLF or LF.
List<List<String>> parseCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (quoted) {
      if (c == '"' && i + 1 < text.length && text[i + 1] == '"') {
        field.write('"');
        i++;
      } else if (c == '"') {
        quoted = false;
      } else {
        field.write(c);
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == ',') {
      row.add(field.toString());
      field.clear();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(field.toString());
      field.clear();
      if (row.any((x) => x.trim().isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      field.write(c);
    }
  }
  row.add(field.toString());
  if (row.any((x) => x.trim().isNotEmpty)) rows.add(row);
  return rows;
}

/// Upload up to 200 products from a spreadsheet saved as CSV (`BulkUpload`).
class BulkUploadSheet extends StatefulWidget {
  const BulkUploadSheet({super.key});

  @override
  State<BulkUploadSheet> createState() => _BulkUploadSheetState();
}

class _BulkUploadSheetState extends State<BulkUploadSheet> {
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _rows = [];
  List<String> _problems = [];
  Map<String, dynamic>? _result;
  String _error = '';
  String _file = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    jlist('/categories', 'categories').then((v) => mounted ? setState(() => _categories = v) : null).catchError((_) {});
  }

  Future<void> _pick() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'CSV', extensions: ['csv'], mimeTypes: ['text/csv', 'text/comma-separated-values'], uniformTypeIdentifiers: ['public.comma-separated-values-text']),
      ],
    );
    if (file == null) return;
    setState(() {
      _error = '';
      _result = null;
      _rows = [];
      _problems = [];
      _file = file.name;
    });
    final table = parseCsv(utf8.decode(await file.readAsBytes(), allowMalformed: true).replaceFirst('﻿', ''));
    if (table.length < 2) {
      setState(() => _error = "The file has no product rows. Use the template's first row as the header.");
      return;
    }
    final header = table.first.map((h) => h.trim()).toList();
    final missing = ['name', 'description', 'price', 'category', 'mainImage'].where((c) => !header.contains(c)).toList();
    if (missing.isNotEmpty) {
      setState(() => _error = 'The header is missing: ${missing.join(', ')}. The columns are: ${_bulkColumns.join(', ')}.');
      return;
    }
    final byName = {for (final c in _categories) strOf(c['name']).trim().toLowerCase(): idOf(c)};
    final found = <Map<String, dynamic>>[];
    final issues = <String>[];
    for (var i = 1; i < table.length; i++) {
      final cells = table[i];
      final r = {for (var j = 0; j < header.length; j++) header[j]: j < cells.length ? cells[j].trim() : ''};
      final categoryId = byName['${r['category']}'.toLowerCase()];
      final rowIssues = <String>[
        if ((r['name'] ?? '').isEmpty) 'name',
        if ((r['description'] ?? '').isEmpty) 'description',
        if (!(numOf(r['price']) > 0)) 'price',
        if (categoryId == null) 'category "${r['category']}" not found',
        if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(r['mainImage'] ?? '')) 'mainImage must be an image link (https://…)',
      ];
      if (rowIssues.isNotEmpty) {
        issues.add('Row ${i + 1}: ${rowIssues.join(', ')}');
        continue;
      }
      found.add({
        'name': r['name'],
        'description': r['description'],
        'price': numOf(r['price']),
        if (numOf(r['discountPrice']) > 0) 'discountPrice': numOf(r['discountPrice']),
        'stockQuantity': numOf(r['stockQuantity']).floor().clamp(0, 1 << 31),
        'category': categoryId,
        if ((r['brand'] ?? '').isNotEmpty) 'brand': r['brand'],
        'mainImage': r['mainImage'],
        'status': '${r['status']}'.toUpperCase() == 'ACTIVE' ? 'ACTIVE' : 'DRAFT',
      });
    }
    if (found.length > 200) {
      setState(() => _error = 'Upload up to 200 products at a time. Split the file and try again.');
      return;
    }
    setState(() {
      _rows = found;
      _problems = issues;
    });
  }

  Future<void> _upload() async {
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final res = await jpost('/products/bulk', {'products': _rows});
      setState(() => _result = res);
    } catch (e) {
      final data = e is ApiException ? e.data : null;
      setState(() {
        if (data is Map && data['results'] != null) _result = asMap(data);
        _error = errorText(e);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final created = numOf(_result?['created']) > 0;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Upload products', style: context.mvH1.copyWith(fontSize: 18)),
            const Tiny('Fill in the template in Excel or Google Sheets, save it as CSV, then choose it here. Products are added as drafts unless the status column says ACTIVE. Up to 200 at a time.'),
            const SizedBox(height: 8),
            OutlineBtn(label: 'Copy template', icon: Icons.copy_rounded, compact: true, onPressed: () => copyText(context, bulkTemplate, 'Template copied. Paste it into a spreadsheet.')),
            const SizedBox(height: 8),
            OutlineBtn(label: _file.isEmpty ? 'Choose CSV file' : 'Change file ($_file)', icon: Icons.upload_file_rounded, compact: true, onPressed: _busy ? null : _pick),
            const SizedBox(height: 12),
            if (_error.isNotEmpty) Notice(text: _error),
            if (_problems.isNotEmpty)
              Notice(
                text: '${_problems.length} row${_problems.length == 1 ? '' : 's'} will be skipped:',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [for (final p in _problems.take(8)) Tiny(p), if (_problems.length > 8) Tiny('…and ${_problems.length - 8} more.')],
                ),
              ),
            if (_rows.isNotEmpty && _result == null) Tiny('${_rows.length} product${_rows.length == 1 ? '' : 's'} ready to upload.'),
            if (_result != null)
              Notice(
                ok: created,
                text: strOf(_result!['message'], created ? 'Products uploaded.' : 'Nothing was uploaded.'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [for (final r in asMaps(_result!['results']).where((r) => r['ok'] != true).take(8)) Tiny('${strOf(r['name'], 'Product ${r['row']}')}: ${r['message']}')],
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: OutlineBtn(label: _result != null ? 'Close' : 'Cancel', onPressed: _busy ? null : () => Navigator.of(context).pop(created))),
                if (_result == null) ...[
                  const SizedBox(width: 10),
                  Expanded(child: GradientButton(label: 'Upload ${_rows.isEmpty ? '' : _rows.length}', loading: _busy, onPressed: _rows.isEmpty ? null : _upload)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Inventory ───────────────────────────────────────────────────────────────
