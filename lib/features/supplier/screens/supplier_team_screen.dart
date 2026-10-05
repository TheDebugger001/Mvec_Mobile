import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/utils.dart';
import '../../../widgets/common.dart';
import '../../../widgets/mv_icon.dart';
import '../models/supplier_team.dart';
import '../permissions.dart';
import '../supplier_dependencies.dart';
import '../widgets/supplier_ops_widgets.dart';

/// The people running the supplier's account, and what each of them can do.
///
/// A supplier rarely works alone, so this page lets them add the staff who pack
/// orders, confirm deliveries and take the payouts — each with a role that
/// carries a fixed set of permissions. The coverage panel then shows which
/// operational areas of the account nobody active can currently handle, which is
/// the gap that actually bites when someone is on leave.
class SupplierTeamScreen extends ConsumerWidget {
  const SupplierTeamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(supplierTeamProvider);
    final summaryAsync = ref.watch(supplierTeamSummaryProvider);
    final fallback = ref.watch(supplierTeamModuleProvider).fallbackReason;
    // Staff without the manage-team permission get a read-only roster rather
    // than buttons that would only fail on the server.
    final canManage = ref.watch(canManageTeamProvider);
    final role = ref.watch(currentSupplierRoleProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHead(
          eyebrow: 'ACCOUNT',
          title: 'Team & staff',
          subtitle:
              'Give everyone who works on your account their own login and only '
              'the access their job needs.',
          actions: [
            FilledButton.icon(
              onPressed:
                  canManage ? () => _openForm(context, ref) : null,
              icon: const Icon(Icons.person_add_alt, size: 17),
              label: const Text('Add team member'),
            ),
          ],
        ),
        if (fallback != null) ...[
          InfoBox(fallback, icon: 'bell'),
          const SizedBox(height: 14),
        ],
        if (!canManage && role != null) ...[
          InfoBox(
            'You are signed in as ${role.label.toLowerCase()}, which cannot '
            'change the team. Ask the account owner if someone needs to be '
            'added or removed.',
            icon: 'shield',
          ),
          const SizedBox(height: 14),
        ],
        switch (summaryAsync) {
          AsyncLoading() => const SizedBox(height: 110, child: LoadingState()),
          AsyncError(:final error) => ErrorState(
            message: friendlyError(error),
            onRetry: () => ref.invalidate(supplierTeamProvider),
          ),
          AsyncData(:final value) => _metrics(context, value),
          _ => const SizedBox(height: 110, child: LoadingState()),
        },
        const SizedBox(height: 16),
        switch (membersAsync) {
          AsyncLoading() => const SizedBox(height: 170, child: LoadingState()),
          AsyncError(:final error) => ErrorState(
            message: friendlyError(error),
            onRetry: () => ref.invalidate(supplierTeamProvider),
          ),
          AsyncData(:final value) => _roster(context, ref, value),
          _ => const SizedBox(height: 170, child: LoadingState()),
        },
        const SizedBox(height: 18),
        DataCard(
          title: 'What each role can do',
          subtitle:
              'Permissions come from the role, so changing a role changes it for '
              'everyone who holds it.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final role in TeamRole.values) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 150,
                        child: Row(
                          children: [
                            MvIcon(
                              role.icon,
                              size: 15,
                              color: context.mv.accentDeep,
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                role.label,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: context.mv.text,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Text(
                          role.description,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.4,
                            color: context.mv.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (role != TeamRole.values.last)
                  Divider(height: 1, color: context.mv.border),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        const InfoBox(
          'Role permissions apply immediately. A staff member only ever sees '
          'the pages their role unlocks — for example a warehouse role cannot '
          'see earnings or request a payout.',
          icon: 'shield',
        ),
      ],
    );
  }

  Widget _metrics(BuildContext context, TeamSummary value) {
    final gaps = value.gaps;
    return SupplierOpsMetricRow(
      metrics: [
        SupplierOpsMetric(
          label: 'People on the account',
          value: '${value.total}',
          icon: 'users',
          caption: '${plural(value.active, 'active')} right now',
        ),
        SupplierOpsMetric(
          label: 'Roles in use',
          value: '${value.byRole.length}',
          icon: 'shield',
          caption: TeamRole.values
              .where((r) => value.countFor(r) > 0)
              .map((r) => r.label)
              .join(', '),
        ),
        SupplierOpsMetric(
          label: 'Coverage',
          value: '${(value.coveredShare * 100).toStringAsFixed(0)}%',
          icon: 'check',
          caption:
              gaps.isEmpty
                  ? 'every area is handled'
                  : '${plural(gaps.length, 'gap')} to fill',
          tone: gaps.isEmpty ? MvColors.successText : MvColors.warningText,
        ),
        SupplierOpsMetric(
          label: 'Pending invites',
          value: '${value.invited}',
          icon: 'bell',
          caption:
              value.invited == 0
                  ? 'nobody waiting to sign in'
                  : 'waiting to accept',
        ),
      ],
    );
  }

  Widget _roster(
    BuildContext context,
    WidgetRef ref,
    List<TeamMember> members,
  ) {
    final canManage = ref.watch(canManageTeamProvider);
    final summary = TeamSummary.fromMembers(members);
    if (members.isEmpty) {
      return DataCard(
        child: EmptyState(
          message:
              'No staff yet. Add the people who help you run orders so they '
              'can each get their own login.',
        ),
      );
    }

    return DataCard(
      title: 'Staff',
      subtitle:
          '${members.length} on the account · tap the pencil to change a role',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < members.length; i++) ...[
            if (i > 0) Divider(height: 1, color: context.mv.border),
            TeamMemberTile(
              member: members[i],
              onEdit:
                  !canManage || members[i].isOwner
                      ? null
                      : () => _openForm(context, ref, member: members[i]),
              onRemove:
                  !canManage || members[i].isOwner
                      ? null
                      : () => _confirmRemove(context, ref, members[i]),
            ),
          ],
          if (summary.gaps.isNotEmpty) ...[
            const SizedBox(height: 10),
            InfoBox(
              'Nobody active can ${summary.gaps.map((g) => g.permission.label.toLowerCase()).join(', ')}. '
              'Add someone with the right role before you need it.',
              icon: 'shield',
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmRemove(
    BuildContext context,
    WidgetRef ref,
    TeamMember member,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text('Remove ${member.fullName}?'),
            content: Text(
              'They lose access to this account immediately. Their catalogue '
              'and order history stays put.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Keep them'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Remove'),
              ),
            ],
          ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(supplierTeamModuleProvider).removeMember(member.id);
      ref.invalidate(supplierTeamProvider);
      if (context.mounted) {
        showMvSnack(context, '${member.fullName} removed', success: true);
      }
    } catch (error) {
      if (context.mounted) showMvSnack(context, friendlyError(error));
    }
  }

  void _openForm(BuildContext context, WidgetRef ref, {TeamMember? member}) {
    showDialog<void>(
      context: context,
      builder: (_) => _TeamMemberForm(member: member),
    );
  }
}

/// The add / edit form.
///
/// The role picker spells out each role's permissions as it is chosen, because
/// widening somebody's access is the one decision on this page that cannot be
/// undone by guesswork later.
class _TeamMemberForm extends ConsumerStatefulWidget {
  const _TeamMemberForm({this.member});

  /// Null when adding somebody new.
  final TeamMember? member;

  @override
  ConsumerState<_TeamMemberForm> createState() => _TeamMemberFormState();
}

class _TeamMemberFormState extends ConsumerState<_TeamMemberForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(
    text: widget.member?.fullName ?? '',
  );
  late final TextEditingController _phone = TextEditingController(
    text: widget.member?.phone ?? '',
  );
  late final TextEditingController _email = TextEditingController(
    text: widget.member?.email ?? '',
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.member?.note ?? '',
  );
  late TeamRole _role = widget.member?.role ?? TeamRole.operations;
  late TeamMemberStatus _status =
      widget.member?.status ?? TeamMemberStatus.active;
  bool _saving = false;

  bool get _isEditing => widget.member != null;

  /// Confirms the number as it is typed: MTN · +250 78 800 0000. Without this a
  /// rejected number only says it is wrong, which is unhelpful when several
  /// formats are accepted.
  String? _phoneHelper() {
    final carrier = rwandanCarrier(_phone.text);
    if (carrier == null) return null;
    return '$carrier · ${formatRwandanPhone(_phone.text)}';
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    final service = ref.read(supplierTeamModuleProvider);
    // Blank optional fields are stored as absent rather than as empty strings,
    // so the roster never shows a dangling separator for a member with no email.
    final email = _email.text.trim().isEmpty ? null : _email.text.trim();
    final note = _note.text.trim().isEmpty ? null : _note.text.trim();
    try {
      if (_isEditing) {
        await service.updateMember(
          widget.member!.id,
          fullName: _name.text,
          phone: _phone.text,
          role: _role,
          status: _status,
          email: email,
          note: note,
        );
      } else {
        await service.addMember(
          fullName: _name.text,
          phone: _phone.text,
          role: _role,
          email: email,
          note: note,
        );
      }
      ref.invalidate(supplierTeamProvider);
      if (mounted) {
        Navigator.pop(context);
        showMvSnack(
          context,
          _isEditing
              ? '${_name.text.trim()} updated'
              : 'Invite sent to ${_name.text.trim()}',
          success: true,
        );
      }
    } catch (error) {
      if (mounted) showMvSnack(context, friendlyError(error));
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Ownership is fixed on the account, so it is never offered here.
    final roles = TeamRole.values.where((role) => !role.isProtected).toList();

    return AlertDialog(
      title: Text(_isEditing ? 'Edit team member' : 'Add a team member'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Full name',
                    border: OutlineInputBorder(),
                  ),
                  validator:
                      (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Enter their name'
                              : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Phone number',
                    hintText: '+250 788 000 000',
                    helperText: _phoneHelper(),
                    border: const OutlineInputBorder(),
                  ),
                  validator: rwandanPhoneError,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _note,
                  decoration: const InputDecoration(
                    labelText: 'What they handle (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_isEditing &&
                    widget.member!.status != TeamMemberStatus.active) ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<TeamMemberStatus>(
                    initialValue: _status,
                    decoration: const InputDecoration(
                      labelText: 'Access',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final status in TeamMemberStatus.values)
                        DropdownMenuItem(
                          value: status,
                          child: Text(status.label),
                        ),
                    ],
                    onChanged:
                        (value) => setState(() => _status = value ?? _status),
                  ),
                ],
                const SizedBox(height: 16),
                Text('Role', style: context.mvH1.copyWith(fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                  'The role decides what they can see and do on this account.',
                  style: TextStyle(fontSize: 11, color: context.mv.textMuted),
                ),
                const SizedBox(height: 10),
                TeamRolePicker(
                  role: _role,
                  enabledRoles: roles,
                  onChanged: (value) => setState(() => _role = value),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(
            _saving
                ? 'Saving…'
                : _isEditing
                ? 'Save changes'
                : 'Send invite',
          ),
        ),
      ],
    );
  }
}
