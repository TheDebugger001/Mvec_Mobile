import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../widgets/common.dart';

/// "Needs your attention" queue, refreshed every minute (`AttentionQueue`).
class AttentionQueue extends StatefulWidget {
  const AttentionQueue({super.key});

  @override
  State<AttentionQueue> createState() => _AttentionQueueState();
}

class _AttentionQueueState extends State<AttentionQueue> {
  late final _data = Loader(() => jget('/admin/attention'));
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _data.reload());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _data,
      builder: (context, _) {
        final d = _data.data;
        final items = asMaps(d?['items']).where((i) => numOf(i['count']) > 0).toList();
        final total = numOf(d?['total']).toInt();
        return Section(
          title: 'Needs your attention',
          subtitle:
              d == null
                  ? 'Checking…'
                  : items.isNotEmpty
                  ? '$total thing${total == 1 ? '' : 's'} waiting · updates every minute'
                  : 'Updates every minute',
          trailing: IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh_rounded), onPressed: _data.reload),
          children: [
            if (_data.error != null) Notice(text: errorText(_data.error!)),
            if (d != null && items.isEmpty) const EmptyState(icon: Icons.task_alt_rounded, title: 'All clear', message: 'Nothing is waiting for an administrator right now.'),
            for (final it in items)
              RecordCard(
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: it['urgent'] == true ? (context.isDarkMode ? const Color(0xFF3A1414) : MvColors.errorBg) : context.mv.soft,
                  child: Text('${numOf(it['count']).toInt()}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: it['urgent'] == true ? MvColors.errorText : context.mv.accentDeep)),
                ),
                title: strOf(it['label']),
                subtitle: strOf(it['hint']),
                onTap: strOf(it['link']).startsWith('/') ? () => context.go(strOf(it['link'])) : null,
              ),
          ],
        );
      },
    );
  }
}
