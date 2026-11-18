import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api_client.dart';
import '../../core/upload.dart';
import '../../core/format.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../widgets/common.dart';

const _kinds = [('NATIONAL_ID', 'National ID or passport'), ('BUSINESS_REGISTRATION', 'RDB business registration'), ('TIN', 'TIN certificate'), ('OTHER', 'Other document')];

/// A seller's (or supplier's) ID and business papers for Ikiguzi's review.
/// Files are private; only the seller and Ikiguzi can open them.
/// [profilePath] is `/vendors/me/profile` or `/suppliers/me/profile`.
class SellerDocumentsSection extends StatefulWidget {
  const SellerDocumentsSection({super.key, required this.documents, required this.profilePath, required this.onSaved, this.patch = true});
  final List<Map<String, dynamic>> documents;
  final String profilePath;
  final VoidCallback onSaved;

  /// The supplier profile is saved with PUT; the seller's with PATCH.
  final bool patch;

  @override
  State<SellerDocumentsSection> createState() => _SellerDocumentsSectionState();
}

class _SellerDocumentsSectionState extends State<SellerDocumentsSection> {
  String _kind = 'NATIONAL_ID';
  bool _busy = false;

  Future<void> _save(List<Map<String, dynamic>> docs) async {
    final body = {'documents': docs};
    widget.patch ? await jpatch(widget.profilePath, body) : await jput(widget.profilePath, body);
  }

  Future<void> _add() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2000, imageQuality: 90);
    if (f == null || !mounted) return;
    setState(() => _busy = true);
    final ok = await runAction(context, () async {
      final form = FormData()..files.add(MapEntry('documents', await imagePart(f)));
      final up = asMaps(asMap(await Api.instance.upload('/uploads/documents', form))['documents']);
      await _save([...widget.documents, for (final d in up) {'kind': _kind, 'url': d['url'], 'name': d['name']}]);
    }, success: 'Document added. Ikiguzi reviews it with your profile.');
    if (mounted) setState(() => _busy = false);
    if (ok) widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    return Section(
      title: 'Verification documents',
      subtitle: 'Only you and Ikiguzi can see them',
      children: [
        const Tiny('Ikiguzi verifies sellers before their products appear in the marketplace, and verified sellers get a badge buyers trust. Add a photo of your ID and, if you have one, your RDB business registration.'),
        const SizedBox(height: 8),
        for (final d in widget.documents)
          Row(children: [
            const Icon(Icons.description_outlined, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('${strOf(d['label'], strOf(d['kind']))} · ${formatDate(d['uploadedAt'])}', style: const TextStyle(fontSize: 13))),
            IconButton(tooltip: 'Remove document', icon: const Icon(Icons.close_rounded, size: 18), onPressed: _busy ? null : () async {
              if (await runAction(context, () => _save(widget.documents.where((x) => x['url'] != d['url']).toList()), success: 'Removed.')) widget.onSaved();
            }),
          ]),
        const SizedBox(height: 6),
        FilterSelect(label: 'Document', value: _kind, options: _kinds, onChanged: (v) => setState(() => _kind = v)),
        OutlineBtn(label: _busy ? 'Uploading…' : 'Upload a photo', icon: Icons.upload_file_rounded, compact: true, onPressed: _busy ? null : _add),
      ],
    );
  }
}
