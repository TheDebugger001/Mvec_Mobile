import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../widgets/common.dart';

/// `/admin/settings` — fees, rules, auto-release, providers and jobs.
class AdminPlatformPage extends StatefulWidget {
  const AdminPlatformPage({super.key});

  @override
  State<AdminPlatformPage> createState() => _AdminPlatformPageState();
}

class _AdminPlatformPageState extends State<AdminPlatformPage> {
  late final _data = Loader(() => jget('/admin/platform'));
  late final _ops = Loader(() async => asMap((await jget('/admin/operations-settings'))['settings']));
  final _days = TextEditingController();
  final _reply = TextEditingController();
  bool _filled = false;
  bool _busy = false;

  @override
  void dispose() {
    _data.dispose();
    _ops.dispose();
    _days.dispose();
    _reply.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_days.text.isEmpty || _reply.text.isEmpty) return;
    setState(() => _busy = true);
    final days = numOf(_days.text), reply = numOf(_reply.text);
    final ok = await runAction(
      context,
      () => jput('/admin/operations-settings', {'autoReleaseDays': days, 'disputeResponseDays': reply}),
      success:
          'Saved. ${days > 0 ? 'Sellers are paid automatically ${_days.text} day${days == 1 ? '' : 's'} after shipping if no problem is reported.' : 'Automatic release is off.'} Sellers have ${_reply.text} day${reply == 1 ? '' : 's'} to answer a problem report before Ikiguzi steps in.',
    );
    if (mounted) setState(() => _busy = false);
    if (ok) _data.reload();
  }

  Widget _line(String label, String value, [String? detail]) => RecordCard(title: label, subtitle: detail, amount: value);

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'Platform',
      title: 'Platform settings',
      subtitle: 'How Ikiguzi is set up right now, read live from the server.',
      onRefresh: _data.reload,
      children: [
        LoadView(
          loader: _data,
          loadingLabel: 'Loading settings…',
          builder:
              (d) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Section(title: 'Fees', children: [for (final f in asMaps(d['fees'])) _line(strOf(f['label']), strOf(f['value']), strOf(f['detail']))]),
                  Section(title: 'Rules', children: [for (final f in asMaps(d['rules'])) _line(strOf(f['label']), strOf(f['value']))]),
                  ListenableBuilder(
                    listenable: _ops,
                    builder: (context, _) {
                      final s = _ops.data;
                      if (s != null && !_filled) {
                        _filled = true;
                        _days.text = '${s['autoReleaseDays']}';
                        _reply.text = '${s['disputeResponseDays'] ?? 3}';
                      }
                      return Section(
                        title: 'Paying sellers and problem reports',
                        children: [
                          const Tiny(
                            'If a buyer neither gives the delivery code nor reports a problem, the seller is paid automatically this many days after the order ships. Buyers are told when their order ships. A reported problem freezes the payment. Pickup orders wait for collection. 0 turns it off.',
                          ),
                          if (s == null && _ops.error == null) const LoadingState(),
                          if (_ops.error != null) Notice(text: errorText(_ops.error!)),
                          if (s != null) ...[
                            const SizedBox(height: 8),
                            TextField(
                              controller: _days,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Pay sellers this many days after shipping', helperText: '0 to 30'),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _reply,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Days a seller has to answer a problem report', helperText: '1 to 14'),
                            ),
                            const SizedBox(height: 10),
                            GradientButton(label: 'Save', loading: _busy, onPressed: _save),
                          ],
                        ],
                      );
                    },
                  ),
                  Section(
                    title: 'Payment providers & messages',
                    subtitle: "“Test mode” means payments succeed without real money. Add the keys to the server's .env to go live.",
                    children: [for (final i in asMaps(d['integrations'])) RecordCard(title: strOf(i['label']), subtitle: strOf(i['env']), status: Pill(i['status'], label: strOf(i['status'])))],
                  ),
                  Section(
                    title: 'Automatic jobs',
                    subtitle: 'Environment: ${d['environment'] ?? ''}',
                    children: [for (final j in asMaps(d['jobs'])) _line(strOf(j['label']), strOf(j['schedule']), strOf(j['detail']))],
                  ),
                  InfoBox(
                    title: 'Change rates and shares',
                    text: 'Commission per category, seller overrides, the affiliate share and who pays provider fees are all set on the Commission rules page.',
                    child: GradientButton(label: 'Open commission rules', compact: true, onPressed: () => context.go('/admin/commission-rules')),
                  ),
                ],
              ),
        ),
      ],
    );
  }
}

// ─── Audit log ──────────────────────────────────────────────────────────────
