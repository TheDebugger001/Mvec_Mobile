import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../widgets/common.dart';

String? _waLink(String phone) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  final intl =
      digits.startsWith('250')
          ? digits
          : digits.startsWith('0')
          ? '25$digits'
          : digits;
  return intl.isEmpty ? null : 'https://wa.me/$intl';
}

/// `/vendor/customers` — everyone who bought from the seller.
class SellerCustomersPage extends StatefulWidget {
  const SellerCustomersPage({super.key});

  @override
  State<SellerCustomersPage> createState() => _SellerCustomersPageState();
}

class _SellerCustomersPageState extends State<SellerCustomersPage> {
  late final _data = Loader(() => jlist('/users/vendor/customers', 'data'));
  String _type = '';
  String _q = '';

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  void _open(Map<String, dynamic> c) {
    showModalBottomSheet<void>(context: context, isScrollControlled: true, useSafeArea: true, showDragHandle: true, builder: (_) => _CustomerSheet(customerKey: strOf(c['key'] ?? c['id'])));
  }

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'Seller platform',
      title: 'Customers',
      subtitle: 'Everyone who bought from you: Ikiguzi buyers and the guest customers from your manual orders.',
      onRefresh: _data.reload,
      children: [
        LoadView(
          loader: _data,
          builder: (all) {
            final repeat = all.where((c) => numOf(c['orders']) > 1).length;
            final orders = all.fold<num>(0, (s, c) => s + numOf(c['orders']));
            final spent = all.fold<num>(0, (s, c) => s + numOf(c['totalSpent']));
            final top = all.firstOrNull;
            final rows = all.where((c) => (_type.isEmpty || (_type == 'guest' ? c['guest'] == true : c['guest'] != true)) && matches(_q, [c['name'], c['phone'], c['email'], c['city']])).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MetricGrid(
                  children: [
                    MetricCard(label: 'Customers', value: '${all.length}', icon: 'users', sub: '${all.where((c) => c['guest'] == true).length} guests'),
                    MetricCard(label: 'Repeat customers', value: '$repeat', icon: 'heart', sub: all.isEmpty ? 'No customers yet' : '${(repeat / all.length * 100).round()}% bought again'),
                    MetricCard(label: 'Average order', value: money(orders == 0 ? 0 : spent / orders), icon: 'cart', sub: 'Your items per order'),
                    MetricCard(label: 'Top customer', value: top == null ? '—' : money(top['totalSpent']), icon: 'wallet', sub: strOf(top?['name'])),
                  ],
                ),
                const SizedBox(height: 14),
                if (all.isEmpty)
                  const EmptyState(icon: Icons.group_outlined, title: 'No customers yet', message: 'Customers appear here after their first order with you.')
                else ...[
                  SearchBox(hint: 'Search name, phone, email or city…', onChanged: (v) => setState(() => _q = v)),
                  FilterSelect(
                    label: 'Customer type',
                    value: _type,
                    options: const [('', 'All customers'), ('buyer', 'Ikiguzi buyers'), ('guest', 'Guests')],
                    onChanged: (v) => setState(() => _type = v),
                  ),
                  const SizedBox(height: 12),
                  Paged<Map<String, dynamic>>(
                    items: rows,
                    empty: const Tiny('No customers match.'),
                    itemBuilder:
                        (c) => RecordCard(
                          title: strOf(c['name']),
                          subtitle: strOf(c['phone'] ?? c['email']),
                          lines: [
                            '${c['city'] ?? '—'} · ${numOf(c['orders']).toInt()} orders${numOf(c['cancelledOrders']) > 0 ? ' (${c['cancelledOrders']} cancelled)' : ''}',
                            'Last purchase ${formatDate(c['lastPurchase'])}',
                          ],
                          amount: money(c['totalSpent']),
                          status: StatusChip(c['guest'] == true ? 'Guest' : 'Buyer', tone: c['guest'] == true ? StatusTone.warn : StatusTone.good),
                          onTap: () => _open(c),
                        ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _CustomerSheet extends StatefulWidget {
  const _CustomerSheet({required this.customerKey});
  final String customerKey;

  @override
  State<_CustomerSheet> createState() => _CustomerSheetState();
}

class _CustomerSheetState extends State<_CustomerSheet> {
  late final _data = Loader(() => jget('/users/vendor/customers/${Uri.encodeComponent(widget.customerKey)}'));
  bool _messaging = false;

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
      child: LoadView(
        loader: _data,
        builder: (d) {
          final c = asMap(d['customer']);
          final phone = strOf(c['phone']);
          final email = strOf(c['email']);
          final wa = phone.isEmpty ? null : _waLink(phone);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Avatar(name: strOf(c['name'], '?'), radius: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(strOf(c['name']), style: context.mvH1.copyWith(fontSize: 18)),
                        Tiny('${c['guest'] == true ? 'Guest customer (no Ikiguzi account)' : 'Ikiguzi buyer'}${strOf(c['city']).isNotEmpty ? ' · ${c['city']}' : ''}'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (phone.isNotEmpty) ActionChipBtn(phone, icon: Icons.call_outlined, onPressed: () => launchUrl(Uri.parse('tel:$phone'))),
                  if (email.isNotEmpty) ActionChipBtn(email, icon: Icons.mail_outline_rounded, onPressed: () => launchUrl(Uri.parse('mailto:$email'))),
                  if (wa != null) ActionChipBtn('WhatsApp', icon: Icons.chat_outlined, onPressed: () => launchUrl(Uri.parse(wa), mode: LaunchMode.externalApplication)),
                ],
              ),
              const SizedBox(height: 12),
              MetricGrid(
                children: [
                  MetricCard(label: 'Orders', value: '${numOf(c['orders']).toInt()}', icon: 'cart'),
                  MetricCard(label: 'Total spent', value: money(c['totalSpent']), icon: 'wallet'),
                  MetricCard(label: 'Average order', value: money(c['averageOrder']), icon: 'chart'),
                  MetricCard(label: 'Customer since', value: formatDate(c['firstPurchase']), icon: 'users'),
                ],
              ),
              const SizedBox(height: 12),
              const Text('Order history', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              for (final o in asMaps(d['orders']))
                RecordCard(
                  title: strOf(o['orderNumber']),
                  badges: [if (o['source'] == 'MANUAL') const StatusChip('Manual')],
                  subtitle: '${formatDate(o['createdAt'])} · ${asMaps(o['items']).map((i) => '${i['quantity']}× ${i['name']}').join(', ')}',
                  amount: money(numOf(o['subtotal']) + numOf(o['delivery'])),
                  status: Pill(o['orderStatus']),
                  onTap: () {
                    Navigator.of(context).pop();
                    context.push('/vendor/orders/${idOf(o)}');
                  },
                ),
              if (c['guest'] != true) ...[
                const SizedBox(height: 8),
                GradientButton(
                  label: 'Message customer',
                  icon: Icons.chat_bubble_outline_rounded,
                  loading: _messaging,
                  onPressed: () async {
                    setState(() => _messaging = true);
                    try {
                      await jpost('/conversations', {'recipientId': idOf(c)});
                      if (context.mounted) {
                        Navigator.of(context).pop();
                        context.go('/vendor/messages');
                      }
                    } catch (e) {
                      if (context.mounted) toast(context, errorText(e), error: true);
                      if (mounted) setState(() => _messaging = false);
                    }
                  },
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

// ─── Categories ──────────────────────────────────────────────────────────────
