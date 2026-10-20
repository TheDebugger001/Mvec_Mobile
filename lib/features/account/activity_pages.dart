import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/account_api.dart';
import '../../api/commerce_api.dart';
import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../state/auth_state.dart';
import '../../state/notifications_state.dart';
import '../../widgets/common.dart';
import '../common/page_frame.dart';
import '../../portal/shared_pages.dart';

/// `/buyer/notifications` — the account's notifications (`NotificationPanel`).
class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String _error = '';
  bool _unreadOnly = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await NotificationsApi.mine();
      if (mounted) {
        setState(() {
          _items = r.items;
          _error = '';
        });
        ref.read(unreadProvider.notifier).set(r.unread);
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markRead(Map<String, dynamic> n) async {
    if (n['isRead'] == true) return;
    setState(() => _items = [for (final x in _items) x['id'] == n['id'] ? {...x, 'isRead': true} : x]);
    ref.read(unreadProvider.notifier).set((ref.read(unreadProvider) - 1).clamp(0, 1 << 20));
    try {
      await NotificationsApi.markRead(strOf(n['id'] ?? n['_id']));
    } catch (_) {
      // The next refresh restores the real state.
    }
  }

  Future<void> _markAll() async {
    setState(() => _items = [for (final x in _items) {...x, 'isRead': true}]);
    ref.read(unreadProvider.notifier).set(0);
    try {
      await NotificationsApi.markAllRead();
    } catch (_) {
      // The next refresh restores the real state.
    }
  }

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    final unread = _items.where((n) => n['isRead'] != true).length;
    final shown = _unreadOnly ? _items.where((n) => n['isRead'] != true).toList() : _items;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [
          PageTitle(eyebrow: 'Notifications', title: 'Notifications', subtitle: unread > 0 ? '$unread unread' : 'You are all caught up.', trailing: unread > 0 ? TextButton(onPressed: _markAll, child: const Text('Mark all read')) : null),
          Row(children: [
            ChoiceChip(label: const Text('All'), selected: !_unreadOnly, onSelected: (_) => setState(() => _unreadOnly = false), showCheckmark: false),
            const SizedBox(width: 8),
            ChoiceChip(label: const Text('Unread'), selected: _unreadOnly, onSelected: (_) => setState(() => _unreadOnly = true), showCheckmark: false),
          ]),
          const SizedBox(height: 10),
          if (_loading) const LoadingState(),
          if (_error.isNotEmpty) ErrorState(error: _error, onRetry: _load),
          if (!_loading && _error.isEmpty && shown.isEmpty) const EmptyState(icon: Icons.notifications_none_rounded, title: 'No notifications', message: 'Order, payment and delivery updates show up here.'),
          for (final n in shown)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(color: n['isRead'] == true ? mv.surface : mv.soft, border: Border.all(color: mv.border), borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                onTap: () {
                  _markRead(n);
                  final link = strOf(n['link']);
                  if (link.startsWith('/') && !link.startsWith('//')) context.push(link);
                },
                dense: true,
                leading: Icon(n['isRead'] == true ? Icons.notifications_none_rounded : Icons.notifications_active_outlined, color: mv.accentDeep, size: 22),
                title: Text(strOf(n['title'], 'Notification'), style: TextStyle(fontWeight: n['isRead'] == true ? FontWeight.w500 : FontWeight.w700, fontSize: 13)),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(strOf(n['body']), style: const TextStyle(fontSize: 12.5)), const SizedBox(height: 2), Text(formatDateTime(n['createdAt']), style: TextStyle(color: mv.textMuted, fontSize: 11))]),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Messages ────────────────────────────────────────────────────────────────

Map<String, dynamic> _other(Map<String, dynamic> conversation, String myId) {
  final people = asMaps(conversation['participants']);
  return people.firstWhere((p) => idOf(p) != myId, orElse: () => <String, dynamic>{});
}

String _personName(Map<String, dynamic> p) => strOf(p['companyName'] ?? p['fullName'] ?? p['Fullname'], 'MVEC user');

/// `/buyer/messages` — direct conversations with sellers (`pages/Messages.jsx`).
class MessagesPage extends ConsumerStatefulWidget {
  const MessagesPage({super.key});

  @override
  ConsumerState<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends ConsumerState<MessagesPage> {
  List<Map<String, dynamic>> _conversations = const [];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await ConversationsApi.all();
      c.sort((a, b) => (parseDate(b['lastMessageAt']) ?? DateTime(2000)).compareTo(parseDate(a['lastMessageAt']) ?? DateTime(2000)));
      if (mounted) {
        setState(() {
          _conversations = c;
          _error = '';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _newChat() async {
    final contact = await showModalBottomSheet<Map<String, dynamic>>(context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => const _ContactSearch());
    if (contact == null) return;
    try {
      final c = await ConversationsApi.create({'recipientId': idOf(contact)});
      if (mounted) {
        await context.push('/buyer/messages/${idOf(c)}');
        _load();
      }
    } catch (e) {
      if (mounted) toast(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    final me = ref.watch(authProvider.select((a) => a.user?.id)) ?? '';
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [
          PageTitle(eyebrow: 'Messages', title: 'Messages', subtitle: 'Keep buyer and seller conversations organized.', trailing: OutlineBtn(label: 'New', compact: true, icon: Icons.add_rounded, onPressed: _newChat)),
          if (_loading) const LoadingState(),
          if (_error.isNotEmpty) ErrorState(error: _error, onRetry: _load),
          if (!_loading && _error.isEmpty && _conversations.isEmpty) const EmptyState(icon: Icons.chat_bubble_outline_rounded, title: 'No conversations yet', message: 'Tap New to message a store.'),
          for (final c in _conversations)
            Builder(builder: (_) {
              final other = _other(c, me);
              final unread = numOf(c['unreadCount']).toInt();
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(color: mv.surface, border: Border.all(color: mv.border), borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  onTap: () async {
                    await context.push('/buyer/messages/${idOf(c)}');
                    _load();
                  },
                  leading: Avatar(name: _personName(other), url: strOf(other['logoUrl'])),
                  title: Text(_personName(other), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                  subtitle: Text(strOf(c['lastMessage'], 'Say hello…'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
                  trailing: unread > 0 ? CircleAvatar(radius: 10, backgroundColor: MvColors.skyBlue, child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 10))) : Text(formatDate(c['lastMessageAt']), style: TextStyle(color: mv.textMuted, fontSize: 10.5)),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _ContactSearch extends StatefulWidget {
  const _ContactSearch();

  @override
  State<_ContactSearch> createState() => _ContactSearchState();
}

class _ContactSearchState extends State<_ContactSearch> {
  final _q = TextEditingController();
  List<Map<String, dynamic>> _results = const [];
  bool _busy = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _search(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (q.trim().length < 2) {
        setState(() => _results = const []);
        return;
      }
      setState(() => _busy = true);
      try {
        final r = await ConversationsApi.contacts(q.trim());
        if (mounted) setState(() => _results = r);
      } catch (_) {
        // No results shown on failure.
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SizedBox(
        height: 380,
        child: Column(
          children: [
            TextField(controller: _q, autofocus: true, onChanged: _search, decoration: const InputDecoration(hintText: 'Search stores or people…', prefixIcon: Icon(Icons.search_rounded, size: 20))),
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: ListView(children: [
                for (final c in _results) ListTile(leading: Avatar(name: _personName(c), url: strOf(c['logoUrl'])), title: Text(_personName(c)), subtitle: Text(strOf(c['role'])), onTap: () => Navigator.pop(context, c)),
                if (_results.isEmpty && !_busy) const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('Type at least 2 letters.'))),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

/// `/buyer/messages/:id` — one conversation. (Refreshes every few seconds.)
class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key, required this.id});
  final String id;

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  List<Map<String, dynamic>> _messages = const [];
  bool _loading = true;
  String _error = '';
  final _text = TextEditingController();
  final _scroll = ScrollController();
  Timer? _timer;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 6), (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    try {
      final m = await ConversationsApi.messages(widget.id);
      if (!mounted) return;
      final grew = m.length != _messages.length;
      setState(() {
        _messages = m;
        _error = '';
      });
      if (grew) {
        ConversationsApi.markRead(widget.id).catchError((_) {});
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
        });
      }
    } catch (e) {
      if (mounted && !quiet) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ConversationsApi.send(widget.id, t);
      _text.clear();
      await _load();
    } catch (e) {
      if (mounted) toast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    final me = ref.watch(authProvider.select((a) => a.user?.id)) ?? '';
    return PageFrame(
      title: 'Conversation',
      fallback: '/buyer/messages',
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const LoadingState()
                : _error.isNotEmpty
                    ? ErrorState(error: _error, onRetry: _load)
                    : _messages.isEmpty
                        ? const EmptyState(icon: Icons.chat_bubble_outline_rounded, title: 'Say hello', message: 'Messages in this conversation appear here.')
                        : ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.all(14),
                            itemCount: _messages.length,
                            itemBuilder: (_, i) {
                              final m = _messages[i];
                              final sender = m['senderId'] ?? idOf(m['sender']);
                              final mine = '$sender' == me;
                              return Align(
                                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .75),
                                  decoration: BoxDecoration(color: mine ? MvColors.skyBlue : mv.surfaceMuted, borderRadius: BorderRadius.circular(14)),
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                    Text(strOf(m['content']), style: TextStyle(color: mine ? Colors.white : mv.text, fontSize: 13)),
                                    Text(formatDateTime(m['createdAt']), style: TextStyle(color: mine ? Colors.white70 : mv.textMuted, fontSize: 9.5)),
                                  ]),
                                ),
                              );
                            },
                          ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            decoration: BoxDecoration(color: mv.surface, border: Border(top: BorderSide(color: mv.border))),
            child: Row(children: [
              Expanded(child: TextField(controller: _text, minLines: 1, maxLines: 4, textInputAction: TextInputAction.send, onSubmitted: (_) => _send(), decoration: const InputDecoration(hintText: 'Write a message…', isDense: true))),
              IconButton(onPressed: _sending ? null : _send, icon: Icon(Icons.send_rounded, color: mv.accentDeep), tooltip: 'Send'),
            ]),
          ),
        ],
      ),
    );
  }
}

// ─── Refunds ─────────────────────────────────────────────────────────────────

const _disputeReason = {'ITEM_NOT_RECEIVED': 'Item not received', 'DAMAGED_GOODS': 'Damaged goods', 'WRONG_ITEM': 'Wrong item', 'INCOMPLETE_ORDER': 'Incomplete order', 'SLA_BREACH': 'Late delivery', 'OTHER': 'Other'};
const _disputeStatus = {
  'OPEN': ('Open', StatusTone.warn),
  'UNDER_REVIEW': ('Under review', StatusTone.warn),
  'EVIDENCE_SUBMITTED': ('Evidence submitted', StatusTone.warn),
  'RESOLVED_BUYER_REFUNDED': ('Refunded to you', StatusTone.good),
  'RESOLVED_VENDOR_RELEASED': ('Released to seller', StatusTone.neutral),
  'RESOLVED_SPLIT': ('Split settlement', StatusTone.good),
  'REJECTED': ('Rejected', StatusTone.bad),
};

/// `/buyer/refunds` — refund requests the buyer reported.
class RefundsPage extends StatefulWidget {
  const RefundsPage({super.key});

  @override
  State<RefundsPage> createState() => _RefundsPageState();
}

class _RefundsPageState extends State<RefundsPage> {
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await DisputesApi.mine();
      if (mounted) setState(() => _rows = r);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [
          const PageTitle(eyebrow: 'Buyer', title: 'Refunds', subtitle: "Track refund requests you've reported from your orders."),
          DataCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Report a problem with an order', style: TextStyle(fontWeight: FontWeight.w600, color: mv.text)),
              const SizedBox(height: 4),
              Text('Open the order and choose Report a problem to start a refund request.', style: TextStyle(color: mv.textMuted, fontSize: 12.5)),
              const SizedBox(height: 10),
              GradientButton(label: 'View my orders', compact: true, onPressed: () => context.go('/orders')),
            ]),
          ),
          if (_loading) const LoadingState(),
          if (_error.isNotEmpty) ErrorState(error: _error, onRetry: _load),
          if (!_loading && _error.isEmpty && _rows.isEmpty) const EmptyState(title: 'No refund requests yet'),
          for (final r in _rows)
            InkWell(
              onTap: () => openDisputeCase(context, idOf(r), onChanged: _load),
              borderRadius: BorderRadius.circular(12),
              child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: mv.surface, border: Border.all(color: mv.border), borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Expanded(child: Text(strOf(r['disputeNumber']), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))), StatusChip(_disputeStatus[r['status']]?.$1 ?? statusLabel(r['status']), tone: _disputeStatus[r['status']]?.$2 ?? StatusTone.neutral)]),
                const SizedBox(height: 4),
                Text('Order ${strOf(asMap(r['order'])['orderNumber'], '—')} · ${_disputeReason[r['reason']] ?? statusLabel(r['reason'])}', style: TextStyle(color: mv.textMuted, fontSize: 12)),
                Text('${money(r['disputedAmount'])} · ${formatDate(r['createdAt'])}', style: TextStyle(color: mv.textMuted, fontSize: 12)),
                if (strOf(asMap(r['arbitrationDecision'])['decision']).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('MVEC decision: ${statusLabel(asMap(r['arbitrationDecision'])['decision'])}', style: const TextStyle(fontSize: 12.5))),
                Padding(padding: const EdgeInsets.only(top: 6), child: Text('Open the case', style: TextStyle(color: mv.accentDeep, fontWeight: FontWeight.w700, fontSize: 12.5))),
              ]),
            ),
            ),
        ],
      ),
    );
  }
}

// ─── Subscription ────────────────────────────────────────────────────────────

/// `/buyer/subscription` — optional ad-free plan (`BuyerSubscription`).
class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key});

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String _error = '';
  String _notice = '';
  bool _busy = false;
  bool _waiting = false;
  String _method = 'momo';
  final _phone = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await BuyerSubscriptionApi.get();
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _watch(String paymentId) async {
    setState(() => _waiting = true);
    final until = DateTime.now().add(const Duration(minutes: 3));
    while (DateTime.now().isBefore(until) && mounted) {
      try {
        final r = await PaymentsApi.status(paymentId);
        final status = asMap(r['payment'])['status'];
        if (status == 'SUCCESS') {
          await _load();
          if (mounted) {
          setState(() {
                _notice = 'Premium is active. Enjoy shopping without ads!';
                _waiting = false;
              });
        }
          return;
        }
        if (status == 'FAILED' || status == 'CANCELLED') {
          if (mounted) {
          setState(() {
                _error = 'The payment was declined or cancelled. You have not been charged; you can try again.';
                _waiting = false;
              });
        }
          return;
        }
      } catch (_) {
        // Temporary network problem: keep checking.
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    if (mounted) {
          setState(() {
          _waiting = false;
          _notice = 'We have not received the payment confirmation yet. If you approved it, Premium switches on as soon as it arrives.';
        });
        }
  }

  Future<void> _subscribe() async {
    setState(() {
      _error = '';
      _notice = '';
    });
    if (_method == 'momo' && !isRwandanPhone(_phone.text)) {
      setState(() => _error = 'Enter an MTN (078/079) or Airtel (072/073) number.');
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await BuyerSubscriptionApi.checkout(method: _method, phone: _phone.text.trim());
      if (r['status'] == 'SUCCESS') {
        await _load();
        setState(() => _notice = 'Premium is active. Enjoy shopping without ads!');
        return;
      }
      if (_method == 'card') {
        final url = strOf(r['checkoutUrl']);
        if (url.isEmpty) throw ApiException('The card page could not be opened. Please try again.');
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        setState(() => _notice = strOf(r['message'], 'Approve the prompt on your phone.'));
      }
      unawaited(_watch(strOf(r['paymentId'])));
    } catch (e) {
      setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _free() async {
    if (!await confirmDialog(context, 'Switch back to Free? Ads will show again. Time you already paid for is not refunded.', confirm: 'Switch to Free')) return;
    setState(() => _busy = true);
    try {
      final r = await BuyerSubscriptionApi.switchToFree();
      setState(() {
        _data = r;
        _notice = strOf(r['message'], 'You are on the Free plan.');
      });
    } catch (e) {
      setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    final sub = asMap(_data?['subscription']);
    final premiumActive = sub['planKey'] == 'PREMIUM' && sub['status'] == 'Active';
    final premium = asMaps(_data?['tiers']).where((t) => t['planKey'] == 'PREMIUM').firstOrNull;
    final price = premium?['price'] ?? 5000;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      children: [
        const PageTitle(eyebrow: 'Buyer', title: 'Subscription', subtitle: 'Optional ad-free shopping plan.'),
        if (_error.isNotEmpty) Notice(text: _error),
        if (_notice.isNotEmpty) Notice(text: _notice, ok: true),
        if (_loading) const LoadingState(),
        if (!_loading && _data != null) ...[
          DataCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Free', style: TextStyle(fontWeight: FontWeight.w600, color: mv.text)),
              Text('Free forever · ads are shown', style: TextStyle(color: mv.textMuted, fontSize: 12)),
              const SizedBox(height: 8),
              if (!premiumActive) const StatusChip('Your plan') else OutlineBtn(label: 'Switch to Free', compact: true, onPressed: _busy ? null : _free),
            ]),
          ),
          DataCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(strOf(premium?['plan'], 'Buyer Ad Removal'), style: TextStyle(fontWeight: FontWeight.w600, color: mv.text)),
              Text('${money(price)} · ${strOf(premium?['billing'], 'Monthly')} · no ads anywhere on MVEC', style: TextStyle(color: mv.textMuted, fontSize: 12)),
              if (premiumActive) ...[const SizedBox(height: 8), const StatusChip('Your plan'), Text('Active until ${strOf(sub['renewal'])}. Pay again any time to add 30 more days.', style: TextStyle(color: mv.textMuted, fontSize: 11.5))],
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [ButtonSegment(value: 'momo', label: Text('Mobile money')), ButtonSegment(value: 'card', label: Text('Card'))],
                selected: {_method},
                onSelectionChanged: _busy || _waiting ? null : (s) => setState(() => _method = s.first),
                showSelectedIcon: false,
              ),
              const SizedBox(height: 10),
              if (_method == 'momo') TextField(controller: _phone, keyboardType: TextInputType.phone, enabled: !_busy && !_waiting, decoration: const InputDecoration(labelText: 'Mobile money number', hintText: '07xx xxx xxx')),
              const SizedBox(height: 12),
              GradientButton(label: _waiting ? 'Waiting for payment…' : '${premiumActive ? 'Add 30 days' : 'Subscribe'} · ${money(price)}', expand: true, loading: _busy || _waiting, onPressed: _subscribe),
            ]),
          ),
        ],
      ],
    );
  }
}
