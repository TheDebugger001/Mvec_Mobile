import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../api/commerce_api.dart' show getVisitorId, saveVisitorId;
import '../../core/api_client.dart';
import '../../core/config.dart';
import '../../core/format.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../state/auth_state.dart';
import '../../widgets/common.dart';

// The affiliate dashboard (web: pages/AffiliateDashboard.jsx).

String affiliateUrl(dynamic code) => '$webOrigin/track/$code';
const kAffiliateMinimumWithdrawal = 10000;

Future<void> shareLink(BuildContext context, String url, String name) async {
  try {
    await SharePlus.instance.share(ShareParams(text: '$name on MVEC: $url', subject: name));
  } catch (_) {
    if (context.mounted) await copyText(context, url, 'Link copied.');
  }
}

/// `/affiliate` — links, attributed orders and commissions.
class AffiliateOverviewPage extends StatefulWidget {
  const AffiliateOverviewPage({super.key});

  @override
  State<AffiliateOverviewPage> createState() => _AffiliateOverviewPageState();
}

class _AffiliateOverviewPageState extends State<AffiliateOverviewPage> {
  late final _data = Loader(() => jget('/affiliates/overview'));

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'Affiliate platform',
      title: 'Affiliate dashboard',
      subtitle: 'Live performance of your links, attributed orders and commissions.',
      onRefresh: _data.reload,
      children: [
        LoadView(
          loader: _data,
          builder: (d) {
            final links = asMap(d['links']);
            final c = asMap(d['commission']);
            final recent = asMaps(d['recent']);
            final top = asMaps(asMap(d['stats'])['topLinks']);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MetricGrid(
                  children: [
                    MetricCard(
                      icon: 'tag',
                      label: 'Created links',
                      value: '${numOf(links['created']).toInt()}',
                      sub: '${numOf(links['active']).toInt()} active · ${numOf(links['terminated']).toInt()} terminated',
                    ),
                    MetricCard(icon: 'chart', label: 'Clicked links', value: '${numOf(links['clicked']).toInt()}', sub: 'Visited, whether or not they led to a sale'),
                    MetricCard(icon: 'cart', label: 'Successful links', value: '${numOf(links['successful']).toInt()}', sub: 'Clicked, ordered and delivered'),
                    MetricCard(icon: 'chart', label: 'Clicks', value: compact(d['clicks']), sub: '${numOf(d['uniqueVisitors']).toInt()} unique visitors'),
                    MetricCard(
                      icon: 'cart',
                      label: 'Attributed orders',
                      value: '${numOf(d['attributedOrders']).toInt()}',
                      sub: '${numOf(d['conversionRate'])}% of clicks · ${numOf(d['conversions']).toInt()} items',
                    ),
                    MetricCard(icon: 'wallet', label: 'Net commission', value: money(c['net']), sub: '${money(c['reversed'])} reversed by refunds'),
                    MetricCard(icon: 'wallet', label: 'Pending', value: money(c['pending']), sub: 'Held until delivery is confirmed'),
                    MetricCard(icon: 'wallet', label: 'Approved / available', value: money(asMap(d['wallet'])['availableBalance']), sub: 'Minimum withdrawal RWF 10,000'),
                    MetricCard(icon: 'wallet', label: 'Withdrawn', value: money(c['paid']), sub: 'Paid out to you'),
                  ],
                ),
                const SizedBox(height: 14),
                Section(
                  title: 'Recent attributed orders',
                  children: [
                    if (recent.isEmpty)
                      const EmptyState(icon: Icons.receipt_long_outlined, title: 'No attributed orders yet', message: 'Orders placed after a visitor clicks your link will appear here once paid.'),
                    for (final r in recent)
                      RecordCard(
                        title: strOf(r['orderNumber']),
                        subtitle: '${r['product'] ?? ''} · ${formatDate(r['createdAt'])}',
                        lines: ['Item total ${money(r['orderTotal'])}'],
                        amount: money(r['amount']),
                        status: Pill(r['status']),
                      ),
                  ],
                ),
                Section(
                  title: 'Top links (last 30 days)',
                  children: [
                    if (top.isEmpty)
                      EmptyState(
                        icon: Icons.link_rounded,
                        title: 'No links yet',
                        message: 'Create one from Promote Products.',
                        action: OutlineBtn(label: 'Promote products', compact: true, onPressed: () => context.go('/affiliate/products')),
                      ),
                    for (final l in top)
                      RecordCard(
                        title: strOf(asMap(l['targetProduct'])['name'], '—'),
                        subtitle: '${numOf(l['clickCount']).toInt()} clicks · ${numOf(l['conversionCount']).toInt()} orders',
                        amount: money(l['commissionEarned']),
                        status: Pill(l['status']),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// `/affiliate/products` — products sellers opened to affiliates.
class AffiliateProductsPage extends StatefulWidget {
  const AffiliateProductsPage({super.key});

  @override
  State<AffiliateProductsPage> createState() => _AffiliateProductsPageState();
}

class _AffiliateProductsPageState extends State<AffiliateProductsPage> {
  late final _data = Loader(() async {
    final r = await Future.wait([
      jlist('/affiliates/promotable', 'products', {'pageSize': 60}),
      jlist('/affiliates/links', 'data').catchError((_) => <Map<String, dynamic>>[]),
    ]);
    _links = r[1];
    return r[0];
  });
  List<Map<String, dynamic>> _links = [];
  String _q = '';
  String _busy = '';

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  Map<String, dynamic>? _linkFor(dynamic productId) => _links.where((l) => l['status'] != 'TERMINATED' && '${l['targetProductId']}' == '$productId').firstOrNull;

  Future<Map<String, dynamic>?> _create(Map<String, dynamic> p) async {
    setState(() => _busy = '${p['id']}');
    try {
      final res = await jpost('/affiliates/links', {'productId': p['id']});
      final link = asMap(res['link'] ?? res['data']);
      setState(() => _links = [link, ..._links]);
      return link;
    } catch (e) {
      if (mounted) toast(context, errorText(e), error: true);
      return null;
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _terminate(Map<String, dynamic> p) async {
    final link = _linkFor(p['id']);
    if (link == null) return;
    if (!await confirmDialog(
      context,
      'Terminate the affiliate link for ${p['name']}? New visitors will no longer be tracked through it. Your past clicks, orders and commissions are kept.',
      confirm: 'Yes, terminate',
      danger: true,
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = '${p['id']}');
    try {
      await jdelete('/affiliates/links/${idOf(link)}');
      setState(
        () =>
            _links = [
              for (final l in _links) idOf(l) == idOf(link) ? {...l, 'status': 'TERMINATED', 'isActive': false} : l,
            ],
      );
    } catch (e) {
      if (mounted) toast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'Affiliate products',
      title: 'Choose products to promote',
      subtitle: 'Only sellers who opened their products to affiliates appear here. Each card shows what you earn per sale once the buyer confirms delivery.',
      onRefresh: _data.reload,
      children: [
        SearchBox(hint: 'Search products, vendors or categories…', onChanged: (v) => setState(() => _q = v)),
        LoadView(
          loader: _data,
          loadingLabel: 'Loading products…',
          builder: (catalog) {
            if (catalog.isEmpty) {
              return const EmptyState(
                icon: Icons.campaign_outlined,
                title: 'No products to promote yet',
                message: 'Sellers choose whether affiliates may promote their products. As soon as a seller opens the affiliate program, their products and your commission appear here.',
              );
            }
            final shown = catalog.where((p) => matches(_q, [p['name'], p['vendor'], p['category']])).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Tiny('${shown.length} products'),
                Paged<Map<String, dynamic>>(
                  items: shown,
                  perPage: 6,
                  empty: const Tiny('No products match your search.'),
                  itemBuilder: (p) {
                    final link = _linkFor(p['id']);
                    final busy = _busy == '${p['id']}';
                    return RecordCard(
                      leading: ProductImage(src: strOf(p['image']), size: 56, radius: 8),
                      title: strOf(p['name']),
                      subtitle: '${money(p['price'])} · ${p['vendor'] ?? ''}',
                      lines: [
                        'You earn ${money(p['earnPerSale'])} per sale (${p['commissionPercent']}%) · ${numOf(p['stock']).toInt()} in stock',
                        if (link != null) affiliateUrl(link['affiliateCode']),
                      ],
                      actions:
                          link != null
                              ? [
                                ActionChipBtn('Copy link', icon: Icons.copy_rounded, primary: true, onPressed: () => copyText(context, affiliateUrl(link['affiliateCode']), 'Link copied.')),
                                ActionChipBtn('Share', icon: Icons.share_outlined, onPressed: () => shareLink(context, affiliateUrl(link['affiliateCode']), strOf(p['name']))),
                                ActionChipBtn('Terminate link', danger: true, busy: busy, onPressed: () => _terminate(p)),
                              ]
                              : [ActionChipBtn('Create affiliate link', icon: Icons.add_link_rounded, primary: true, busy: busy, onPressed: () => _create(p))],
                    );
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

/// `/affiliate/links` — every link with its clicks and results.
class AffiliateLinksPage extends StatefulWidget {
  const AffiliateLinksPage({super.key});

  @override
  State<AffiliateLinksPage> createState() => _AffiliateLinksPageState();
}

class _AffiliateLinksPageState extends State<AffiliateLinksPage> {
  String _status = 'ALL';
  String _q = '';
  Timer? _debounce;
  late Loader<List<Map<String, dynamic>>> _data = _load();
  String _busy = '';

  Loader<List<Map<String, dynamic>>> _load() => Loader(() => jlist('/affiliates/links', 'data', {'status': _status == 'ALL' ? null : _status, 'q': _q.trim().isEmpty ? null : _q.trim()}));

  void _reload() {
    final old = _data;
    setState(() => _data = _load());
    old.dispose();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'My links',
      title: 'Affiliate links',
      subtitle: 'Every link you created, with its clicks and successful (delivered) orders.',
      onRefresh: () async => _reload(),
      children: [
        SearchBox(
          hint: 'Search by product, label or code…',
          onChanged: (v) {
            _q = v;
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 300), _reload);
          },
        ),
        FilterSelect(
          label: 'Links',
          value: _status,
          options: const [('ALL', 'All links'), ('ACTIVE', 'Active'), ('TERMINATED', 'Terminated')],
          onChanged: (v) {
            _status = v;
            _reload();
          },
        ),
        const SizedBox(height: 12),
        LoadView(
          loader: _data,
          builder:
              (links) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Tiny('${links.length} links'),
                  if (links.isEmpty)
                    EmptyState(
                      icon: Icons.link_rounded,
                      title: 'No links yet',
                      message: 'Create one from Promote Products.',
                      action: OutlineBtn(label: 'Promote products', compact: true, onPressed: () => context.go('/affiliate/products')),
                    ),
                  for (final l in links)
                    Builder(
                      builder: (_) {
                        final active = l['status'] == 'ACTIVE';
                        final paused = active && l['earning'] == false;
                        final url = affiliateUrl(l['affiliateCode']);
                        final name = strOf(asMap(l['targetProduct'])['name'], 'Product');
                        return RecordCard(
                          title: name,
                          badges: [
                            StatusChip(
                              !active
                                  ? 'Terminated'
                                  : paused
                                  ? 'Paused'
                                  : 'Active',
                              tone:
                                  !active
                                      ? StatusTone.neutral
                                      : paused
                                      ? StatusTone.warn
                                      : StatusTone.good,
                            ),
                          ],
                          subtitle: active && !paused && l['commissionPercent'] != null ? '${l['commissionPercent']}% per delivered sale' : null,
                          lines: [
                            if (paused) "${strOf(l['pausedReason'])} New clicks on this link don't earn until the seller opens it again; your past results are kept.",
                            url,
                            'Clicks ${numOf(l['clickCount']).toInt()} · Successful ${numOf(l['successfulCount']).toInt()} · Ordered ${numOf(l['conversionCount']).toInt()}',
                            'Commission ${money(l['commissionEarned'])}',
                            if (!active && l['terminatedAt'] != null) 'Terminated ${formatDate(l['terminatedAt'])}',
                          ],
                          actions:
                              active
                                  ? [
                                    ActionChipBtn('Copy link', icon: Icons.copy_rounded, primary: true, onPressed: () => copyText(context, url, 'Link copied.')),
                                    ActionChipBtn('Share', icon: Icons.share_outlined, onPressed: () => shareLink(context, url, name)),
                                    ActionChipBtn(
                                      'Terminate link',
                                      danger: true,
                                      busy: _busy == idOf(l),
                                      onPressed: () async {
                                        if (!await confirmDialog(
                                          context,
                                          'Terminate the link for $name? New clicks will no longer be tracked. Past clicks, orders and commissions are kept.',
                                          confirm: 'Yes, terminate',
                                          danger: true,
                                        )) {
                                          return;
                                        }
                                        if (!context.mounted) return;
                                        setState(() => _busy = idOf(l));
                                        final ok = await runAction(context, () => jdelete('/affiliates/links/${idOf(l)}'));
                                        if (mounted) setState(() => _busy = '');
                                        if (ok) _reload();
                                      },
                                    ),
                                  ]
                                  : const [],
                        );
                      },
                    ),
                ],
              ),
        ),
      ],
    );
  }
}

/// `/affiliate/commissions` — one line per attributed order item.
class AffiliateCommissionsPage extends StatefulWidget {
  const AffiliateCommissionsPage({super.key});

  @override
  State<AffiliateCommissionsPage> createState() => _AffiliateCommissionsPageState();
}

class _AffiliateCommissionsPageState extends State<AffiliateCommissionsPage> {
  late final _data = Loader(() => jlist('/affiliates/commissions', 'data'));
  String _q = '';

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'Commissions',
      title: 'Commission activity',
      subtitle: 'One line per attributed order item. Refunds show as reversed amounts.',
      onRefresh: _data.reload,
      children: [
        SearchBox(hint: 'Search commissions…', onChanged: (v) => setState(() => _q = v)),
        LoadView(
          loader: _data,
          builder:
              (rows) => Paged<Map<String, dynamic>>(
                items: rows.where((r) => matches(_q, [r['orderNumber'], r['product'], r['status']])).toList(),
                empty: const EmptyState(icon: Icons.payments_outlined, title: 'No commissions yet'),
                itemBuilder:
                    (r) => RecordCard(
                      title: strOf(r['orderNumber']),
                      subtitle: '${r['product'] ?? ''} · ${formatDate(r['createdAt'])}',
                      lines: ['Item total ${money(r['orderTotal'])} · earned ${money(r['commissionAmount'])}${numOf(r['reversedAmount']) > 0 ? ' · reversed ${money(r['reversedAmount'])}' : ''}'],
                      amount: money(r['amount']),
                      status: Pill(r['status']),
                    ),
              ),
        ),
      ],
    );
  }
}

/// `/affiliate/wallet` — commission balance.
class AffiliateWalletPage extends StatefulWidget {
  const AffiliateWalletPage({super.key});

  @override
  State<AffiliateWalletPage> createState() => _AffiliateWalletPageState();
}

class _AffiliateWalletPageState extends State<AffiliateWalletPage> {
  late final _data = Loader(() => jget('/affiliates/wallet'));

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'Affiliate wallet',
      title: 'Wallet',
      subtitle: 'View your commission balance.',
      onRefresh: _data.reload,
      action: GradientButton(label: 'Request withdrawal', compact: true, onPressed: () => context.go('/affiliate/withdrawals')),
      children: [
        LoadView(
          loader: _data,
          builder:
              (w) => MetricGrid(
                children: [
                  MetricCard(icon: 'chart', label: 'Total earned', value: money(w['totalEarned']), sub: 'Lifetime commission'),
                  MetricCard(icon: 'wallet', label: 'Available balance', value: money(w['availableBalance']), sub: 'Ready for withdrawal'),
                  MetricCard(icon: 'wallet', label: 'Pending commission', value: money(w['pendingBalance']), sub: 'Awaiting qualifying completion'),
                ],
              ),
        ),
      ],
    );
  }
}

const _withdrawStatus = {'PENDING': 'Waiting for approval', 'APPROVED': 'Approved', 'PROCESSING': 'Sending', 'COMPLETED': 'Sent', 'REJECTED': 'Not sent'};
const _methods = {'MTN_MOMO': 'MTN MoMo', 'AIRTEL_MONEY': 'Airtel Money', 'BANK_TRANSFER': 'Bank account'};

/// `/affiliate/withdrawals` — request payouts and see their status.
class AffiliateWithdrawalsPage extends StatefulWidget {
  const AffiliateWithdrawalsPage({super.key});

  @override
  State<AffiliateWithdrawalsPage> createState() => _AffiliateWithdrawalsPageState();
}

class _AffiliateWithdrawalsPageState extends State<AffiliateWithdrawalsPage> {
  late final _data = Loader(() async {
    final r = await Future.wait([jget('/affiliates/wallet').catchError((_) => <String, dynamic>{}), jget('/affiliates/payouts').catchError((_) => <String, dynamic>{})]);
    return (wallet: r[0], history: asMaps(r[1]['data']));
  });
  final _amount = TextEditingController();
  final _phone = TextEditingController();
  final _bankName = TextEditingController();
  final _account = TextEditingController();
  final _accountName = TextEditingController();
  String _method = 'MTN_MOMO';
  bool _busy = false;

  @override
  void dispose() {
    _data.dispose();
    for (final c in [_amount, _phone, _bankName, _account, _accountName]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onPhone(String v) {
    final p = mobileProvider(v);
    if (p == 'MTN MoMo') setState(() => _method = 'MTN_MOMO');
    if (p == 'Airtel Money') setState(() => _method = 'AIRTEL_MONEY');
  }

  Future<void> _submit(num available) async {
    final value = numOf(_amount.text);
    final bank = _method == 'BANK_TRANSFER';
    String? problem;
    if (value < kAffiliateMinimumWithdrawal) {
      problem = 'Enter at least RWF 10,000.';
    } else if (value > available) {
      problem = 'That is more than your available balance.';
    } else if (!bank && _phone.text.trim().isEmpty) {
      problem = 'Enter the mobile money number to receive the money.';
    } else if (bank && [_bankName, _account, _accountName].any((c) => c.text.trim().isEmpty)) {
      problem = 'Enter the bank name, account number and account name.';
    }
    if (problem != null) {
      toast(context, problem, error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await jpost('/affiliates/payouts/request', {
        'amount': value,
        'paymentMethod': _method,
        'accountDetails': bank ? {'bankName': _bankName.text.trim(), 'accountNumber': _account.text.trim(), 'accountName': _accountName.text.trim()} : {'phoneNumber': _phone.text.trim()},
      });
      final status = asMap(res['data'])['status'] ?? asMap(res['payout'])['status'];
      if (mounted) {
        toast(
          context,
          status == 'COMPLETED'
              ? '${money(value)} was sent to your mobile money.'
              : status == 'PROCESSING'
              ? '${money(value)} is being sent to your mobile money. You will get a notification when it arrives.'
              : 'Your ${money(value)} withdrawal is waiting for MVEC approval. You will get a notification when it is sent.',
        );
      }
      _amount.clear();
      _data.reload();
    } catch (e) {
      if (mounted) toast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'Affiliate payouts',
      title: 'Withdrawals',
      subtitle: 'Request a payout and track the status of previous withdrawal requests.',
      onRefresh: _data.reload,
      action: OutlineBtn(label: 'View wallet', compact: true, onPressed: () => context.go('/affiliate/wallet')),
      children: [
        LoadView(
          loader: _data,
          builder: (d) {
            final available = numOf(d.wallet['availableBalance']);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Section(
                  title: 'Request a withdrawal',
                  children: [
                    Tiny('Available balance: ${money(available)}. Minimum withdrawal is RWF 10,000.'),
                    const SizedBox(height: 6),
                    TextField(controller: _amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount (RWF)')),
                    const SizedBox(height: 10),
                    FilterSelect(label: 'Payment method', value: _method, options: [for (final e in _methods.entries) (e.key, e.value)], onChanged: (v) => setState(() => _method = v)),
                    const SizedBox(height: 10),
                    if (_method == 'BANK_TRANSFER') ...[
                      TextField(controller: _bankName, decoration: const InputDecoration(labelText: 'Bank name')),
                      const SizedBox(height: 10),
                      TextField(controller: _account, decoration: const InputDecoration(labelText: 'Account number')),
                      const SizedBox(height: 10),
                      TextField(controller: _accountName, decoration: const InputDecoration(labelText: 'Account name')),
                    ] else
                      TextField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'Mobile money number', hintText: '07xx xxx xxx'),
                        onChanged: _onPhone,
                      ),
                    const SizedBox(height: 12),
                    GradientButton(label: 'Withdraw', loading: _busy, onPressed: available < kAffiliateMinimumWithdrawal ? null : () => _submit(available)),
                    if (available < kAffiliateMinimumWithdrawal)
                      const Tiny('You can withdraw once your available balance reaches RWF 10,000. Commissions become available after the buyer confirms delivery.'),
                  ],
                ),
                const Section(
                  title: 'Payout process',
                  children: [
                    Tiny('1. Request a withdrawal to MTN MoMo, Airtel Money or a bank account.'),
                    Tiny('2. Up to RWF 100,000 to mobile money is sent automatically within minutes.'),
                    Tiny('3. Larger amounts and bank transfers are sent after MVEC approval.'),
                    Tiny('4. You get a notification and SMS when the money is sent. A failed transfer returns to your balance.'),
                  ],
                ),
                Section(
                  title: 'Withdrawal history',
                  children: [
                    if (d.history.isEmpty) const Tiny('No withdrawal requests yet.'),
                    for (final r in d.history)
                      RecordCard(
                        title: strOf(r['payoutNumber']),
                        subtitle: '${_methods[r['paymentMethod']] ?? r['paymentMethod']} · ${formatDate(r['createdAt'])}',
                        lines: [if (r['status'] == 'REJECTED' && strOf(r['rejectionReason']).isNotEmpty) 'Not sent · ${r['rejectionReason']}'],
                        amount: money(r['amount']),
                        status: StatusChip(
                          _withdrawStatus[r['status']] ?? '${r['status']}',
                          tone:
                              r['status'] == 'COMPLETED'
                                  ? StatusTone.good
                                  : r['status'] == 'REJECTED'
                                  ? StatusTone.bad
                                  : StatusTone.warn,
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// `/affiliate/profile` — account details and password.
class AffiliateProfilePage extends ConsumerStatefulWidget {
  const AffiliateProfilePage({super.key});

  @override
  ConsumerState<AffiliateProfilePage> createState() => _AffiliateProfilePageState();
}

class _AffiliateProfilePageState extends ConsumerState<AffiliateProfilePage> {
  late final _data = Loader(() => jget('/affiliates/profile'));
  final _c = {
    for (final k in ['fullName', 'phone', 'email', 'displayName', 'website', 'bio', 'current', 'next', 'confirm']) k: TextEditingController(),
  };
  bool _filled = false;
  bool _saving = false;
  bool _savingPw = false;

  @override
  void dispose() {
    _data.dispose();
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _t(String k) => _c[k]!.text.trim();

  Future<void> _save() async {
    if (_t('fullName').length < 2) return toast(context, 'Full name is required.', error: true);
    if (_t('phone').isEmpty) return toast(context, 'Phone number is required.', error: true);
    setState(() => _saving = true);
    try {
      await jpatch('/affiliates/profile', {
        'fullName': _t('fullName'),
        'phone': _t('phone'),
        'email': _t('email'),
        'displayName': _c['displayName']!.text,
        'bio': _c['bio']!.text,
        'website': _c['website']!.text,
      });
      await ref.read(authProvider.notifier).refresh();
      if (mounted) toast(context, 'Profile updated.');
    } catch (e) {
      if (mounted) toast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _password() async {
    if (_c['current']!.text.isEmpty) return toast(context, 'Enter your current password.', error: true);
    if (_c['next']!.text.length < 8) return toast(context, 'New password must be at least 8 characters.', error: true);
    if (_c['next']!.text != _c['confirm']!.text) return toast(context, 'New password and confirmation do not match.', error: true);
    setState(() => _savingPw = true);
    try {
      final res = await jpost('/auth/change-password', {'currentPassword': _c['current']!.text, 'newPassword': _c['next']!.text});
      if (strOf(res['token']).isNotEmpty) await ref.read(authProvider.notifier).replaceToken(strOf(res['token']));
      for (final k in ['current', 'next', 'confirm']) {
        _c[k]!.clear();
      }
      if (mounted) toast(context, 'Password updated.');
    } catch (e) {
      if (mounted) toast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _savingPw = false);
    }
  }

  Widget _field(String k, String label, {TextInputType? type, bool obscure = false, int lines = 1}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(controller: _c[k], keyboardType: type, obscureText: obscure, minLines: 1, maxLines: obscure ? 1 : lines, decoration: InputDecoration(labelText: label)),
  );

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'Affiliate profile',
      title: 'Profile',
      subtitle: 'Manage your account details and password without leaving the dashboard.',
      children: [
        LoadView(
          loader: _data,
          builder: (p) {
            if (!_filled) {
              _filled = true;
              _c['fullName']!.text = strOf(p['Fullname'] ?? p['fullname']);
              for (final k in ['phone', 'email', 'displayName', 'bio', 'website']) {
                _c[k]!.text = strOf(p[k]);
              }
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Section(
                  title: 'Account details',
                  children: [
                    _field('fullName', 'Full name *'),
                    _field('phone', 'Phone number *', type: TextInputType.phone),
                    _field('email', 'Email (optional)', type: TextInputType.emailAddress),
                    _field('displayName', 'Public display name'),
                    _field('website', 'Website', type: TextInputType.url),
                    _field('bio', 'Bio', lines: 4),
                    GradientButton(label: 'Save changes', loading: _saving, onPressed: _save),
                  ],
                ),
                Section(
                  title: 'Change password',
                  children: [
                    _field('current', 'Current password', obscure: true),
                    _field('next', 'New password', obscure: true),
                    _field('confirm', 'Confirm new password', obscure: true),
                    GradientButton(label: 'Update password', loading: _savingPw, onPressed: _password),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// `/track/:code` — an affiliate link opened in the app. The server records the
/// click and returns where to go; the visitor id it mints is kept so checkout
/// credits the affiliate (`AffiliateRedirect`).
class AffiliateTrackPage extends StatefulWidget {
  const AffiliateTrackPage({super.key, required this.code});
  final String code;

  @override
  State<AffiliateTrackPage> createState() => _AffiliateTrackPageState();
}

class _AffiliateTrackPageState extends State<AffiliateTrackPage> {
  @override
  void initState() {
    super.initState();
    _track();
  }

  Future<void> _track() async {
    String target = '/shop';
    try {
      final visitor = await getVisitorId();
      final res = await jget('/affiliates/track/${Uri.encodeComponent(widget.code)}', {'visitorId': visitor.isEmpty ? null : visitor});
      final data = asMap(res['data']);
      await saveVisitorId(strOf(data['visitorId']));
      final product = idOf(data['targetProduct']);
      if (product.isNotEmpty) target = '/product/$product';
    } catch (_) {
      // Unknown or terminated link: land on the shop without crediting anyone.
      if (mounted) toast(context, 'This referral link is no longer active.');
    }
    if (mounted) context.go(target);
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: LoadingState(label: 'Opening the product…'));
}
