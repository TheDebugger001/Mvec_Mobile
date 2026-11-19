import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../portal/kit.dart';
import '../../widgets/common.dart';
import 'rider_api.dart';
import '../../widgets/auto_payout_card.dart';
import 'rider_state.dart';

final _walletProvider = FutureProvider.autoDispose((ref) async {
  final r = await Future.wait<dynamic>([RiderApi.wallet(), RiderApi.withdrawals(), RiderApi.history()]);
  return (wallet: r[0] as Map<String, dynamic>, withdrawals: r[1] as List<Map<String, dynamic>>, delivered: r[2] as List<DeliveryJob>);
});

/// `/delivery/earnings`: what was earned, withdrawing it to mobile money, and
/// the parcels delivered.
class RiderEarningsPage extends ConsumerWidget {
  const RiderEarningsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_walletProvider);
    return data.when(
      loading: () => const LoadingState(),
      error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(_walletProvider)),
      data: (d) {
        final available = numOf(d.wallet['available']);
        final account = ref.watch(riderBoardProvider).valueOrNull?.account;
        return PortalPage(
          eyebrow: 'DELIVERY',
          title: 'Earnings',
          subtitle: 'Each delivered parcel adds its whole delivery fee here.',
          onRefresh: () async => ref.invalidate(_walletProvider),
          children: [
            MetricGrid(children: [
              MetricCard(label: 'Available', value: money(available), icon: 'wallet'),
              MetricCard(label: 'Earned in total', value: money(d.wallet['totalEarned']), sub: '${money(d.wallet['totalWithdrawn'])} withdrawn', icon: 'chart'),
            ]),
            const SizedBox(height: 12),
            AutoPayoutCard(defaultName: account?.name ?? '', defaultPhone: account?.phone ?? '', onSaved: () => ref.invalidate(_walletProvider)),
            const SizedBox(height: 12),
            _WithdrawForm(available: available, minimum: numOf(d.wallet['minimumWithdrawal'], 1000)),
            Section(title: 'Withdrawals', children: [
              if (d.withdrawals.isEmpty) const EmptyState(title: 'No withdrawals yet'),
              for (final w in d.withdrawals)
                RecordCard(
                  title: money(w['amount']),
                  subtitle: '${strOf(asMap(w['payoutDetails'])['accountNumber'])} · ${formatDate(w['createdAt'])}',
                  status: StatusChip.of(strOf(w['status'])),
                ),
            ]),
            Section(title: 'Delivered', children: [
              if (d.delivered.isEmpty) const EmptyState(title: 'No deliveries yet'),
              for (final j in d.delivered)
                RecordCard(title: '${j.pickup.name} → ${j.customerName}', subtitle: '${j.orderNumber} · ${formatDate(j.deliveredAt)}', amount: money(j.fee)),
            ]),
          ],
        );
      },
    );
  }
}

class _WithdrawForm extends ConsumerStatefulWidget {
  const _WithdrawForm({required this.available, required this.minimum});
  final num available;
  final num minimum;

  @override
  ConsumerState<_WithdrawForm> createState() => _WithdrawFormState();
}

class _WithdrawFormState extends ConsumerState<_WithdrawForm> {
  final _amount = TextEditingController();
  final _name = TextEditingController();
  final _number = TextEditingController();
  bool _busy = false;
  String? _message;
  bool _ok = false;

  @override
  void initState() {
    super.initState();
    final account = ref.read(riderBoardProvider).valueOrNull?.account;
    _name.text = account?.name ?? '';
    _number.text = account?.phone ?? '';
  }

  @override
  void dispose() {
    for (final c in [_amount, _name, _number]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final msg = await RiderApi.withdraw(amount: num.tryParse(_amount.text.trim()) ?? 0, accountName: _name.text.trim(), number: _number.text.trim());
      _amount.clear();
      setState(() {
        _ok = true;
        _message = msg;
      });
      ref.invalidate(_walletProvider);
    } catch (e) {
      setState(() {
        _ok = false;
        _message = errorText(e);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Section(
        title: 'Withdraw to mobile money',
        subtitle: 'At least ${money(widget.minimum)}. MTN or Airtel.',
        children: [
          if (_message != null) Notice(text: _message!, ok: _ok),
          TextField(controller: _amount, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Amount (RWF)', hintText: 'Up to ${money(widget.available)}')),
          const SizedBox(height: 10),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Account holder name')),
          const SizedBox(height: 10),
          TextField(controller: _number, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile money number')),
          const SizedBox(height: 12),
          GradientButton(label: 'Withdraw', expand: true, loading: _busy, onPressed: _busy || widget.available < widget.minimum ? null : _submit),
        ],
      );
}
