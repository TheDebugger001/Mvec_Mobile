import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/utils.dart';
import '../../../widgets/common.dart';
import '../models/vendor_team.dart';
import '../vendor_dependencies.dart';

class VendorTeamScreen extends ConsumerStatefulWidget {
  const VendorTeamScreen({super.key});

  @override
  ConsumerState<VendorTeamScreen> createState() => _VendorTeamScreenState();
}

class _VendorTeamScreenState extends ConsumerState<VendorTeamScreen> {
  bool _working = false;

  Future<void> _addMember() async {
    final draft = await showDialog<_NewVendorStaff>(
      context: context,
      builder: (context) => const _AddVendorStaffDialog(),
    );
    if (draft == null || !mounted) return;
    await _run(
      () => ref
          .read(vendorTeamServiceProvider)
          .addMember(email: draft.email, role: draft.role),
      success: 'Team member added',
    );
  }

  Future<void> _editMember(VendorTeamMember member) async {
    final update = await showDialog<_VendorStaffUpdate>(
      context: context,
      builder: (context) => _EditVendorStaffDialog(member: member),
    );
    if (update == null || !mounted) return;
    await _run(
      () => ref
          .read(vendorTeamServiceProvider)
          .updateMember(member, role: update.role, active: update.active),
      success: 'Team member updated',
    );
  }

  Future<void> _removeMember(VendorTeamMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove team member?'),
        content: Text(
          'Remove ${member.name} (${member.email}) from your store?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      () => ref.read(vendorTeamServiceProvider).removeMember(member.id),
      success: 'Team member removed',
    );
  }

  Future<void> _run(
    Future<void> Function() action, {
    required String success,
  }) async {
    setState(() => _working = true);
    try {
      await action();
      ref.invalidate(vendorTeamProvider);
      if (mounted) showMvSnack(context, success, success: true);
    } catch (error) {
      if (mounted) showMvSnack(context, friendlyError(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(vendorTeamProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHead(
          eyebrow: 'STORE ADMIN',
          title: 'Team / staff',
          subtitle:
              'Add people to your store and assign access based on the work '
              'they do.',
          actions: [
            FilledButton.icon(
              onPressed: _working ? null : _addMember,
              icon: const Icon(Icons.person_add_alt_1, size: 17),
              label: const Text('Add team member'),
            ),
          ],
        ),
        const InfoBox(
          'Add an existing MVEC user by email. This adds them to your store; '
          'it does not create a new login. Each role grants the matching '
          'product, order, or analytics access.',
        ),
        const SizedBox(height: 16),
        switch (membersAsync) {
          AsyncLoading() => const SizedBox(height: 220, child: LoadingState()),
          AsyncError(:final error) => ErrorState(
            message: friendlyError(error),
            onRetry: () => ref.invalidate(vendorTeamProvider),
          ),
          AsyncData(:final value) => _memberList(context, value),
          _ => const SizedBox(height: 220, child: LoadingState()),
        },
      ],
    );
  }

  Widget _memberList(BuildContext context, List<VendorTeamMember> members) {
    return DataCard(
      title: 'Store team',
      subtitle:
          '${members.length} team member${members.length == 1 ? '' : 's'}',
      child: members.isEmpty
          ? const EmptyState(
              message: 'No team members yet. Add a registered MVEC user.',
            )
          : Column(
              children: [
                for (final member in members) ...[
                  _memberTile(context, member),
                  if (member != members.last)
                    Divider(height: 1, color: context.mv.border),
                ],
              ],
            ),
    );
  }

  Widget _memberTile(BuildContext context, VendorTeamMember member) {
    final permissions = member.grantedPermissions;
    return ExpansionTile(
      key: ValueKey(member.id),
      tilePadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: context.mv.soft,
        child: Text(
          initials(member.name),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: context.mv.accentDeep,
          ),
        ),
      ),
      title: Text(
        member.name,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${member.email} · ${member.role.label} · ${titleCase(member.status)}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, color: context.mv.textMuted),
      ),
      childrenPadding: const EdgeInsets.only(left: 8, right: 8, bottom: 12),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final permission in permissions)
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(permission),
                ),
              if (permissions.isEmpty)
                const Text(
                  'No additional permissions assigned.',
                  style: TextStyle(fontSize: 12),
                ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: _working ? null : () => _editMember(member),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Change role / status'),
              ),
              TextButton.icon(
                onPressed: _working ? null : () => _removeMember(member),
                icon: const Icon(Icons.person_remove_outlined, size: 16),
                label: const Text('Remove'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NewVendorStaff {
  const _NewVendorStaff(this.email, this.role);

  final String email;
  final VendorTeamRole role;
}

class _VendorStaffUpdate {
  const _VendorStaffUpdate({this.role, this.active});

  final VendorTeamRole? role;
  final bool? active;
}

class _AddVendorStaffDialog extends StatefulWidget {
  const _AddVendorStaffDialog();

  @override
  State<_AddVendorStaffDialog> createState() => _AddVendorStaffDialogState();
}

class _AddVendorStaffDialogState extends State<_AddVendorStaffDialog> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  VendorTeamRole _role = VendorTeamRole.orderManager;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add team member'),
    content: Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'MVEC account email'),
            validator: (value) {
              final email = value?.trim() ?? '';
              if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
                return 'Enter a valid email address';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<VendorTeamRole>(
            initialValue: _role,
            decoration: const InputDecoration(labelText: 'Role'),
            items: [
              for (final role in VendorTeamRole.values)
                DropdownMenuItem(value: role, child: Text(role.label)),
            ],
            onChanged: (role) {
              if (role != null) setState(() => _role = role);
            },
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _role.description,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_formKey.currentState?.validate() == true) {
            Navigator.pop(context, _NewVendorStaff(_email.text.trim(), _role));
          }
        },
        child: const Text('Add member'),
      ),
    ],
  );
}

class _EditVendorStaffDialog extends StatefulWidget {
  const _EditVendorStaffDialog({required this.member});

  final VendorTeamMember member;

  @override
  State<_EditVendorStaffDialog> createState() => _EditVendorStaffDialogState();
}

class _EditVendorStaffDialogState extends State<_EditVendorStaffDialog> {
  late VendorTeamRole _role = widget.member.role;
  late bool _active = widget.member.isActive;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Update ${widget.member.name}'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<VendorTeamRole>(
          initialValue: _role,
          decoration: const InputDecoration(labelText: 'Role'),
          items: [
            for (final role in VendorTeamRole.values)
              DropdownMenuItem(value: role, child: Text(role.label)),
          ],
          onChanged: (role) {
            if (role != null) setState(() => _role = role);
          },
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            _role.description,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Access active'),
          value: _active,
          onChanged: (active) => setState(() => _active = active),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final roleChanged = _role != widget.member.role;
          final statusChanged = _active != widget.member.isActive;
          if (!roleChanged && !statusChanged) {
            Navigator.pop(context);
            return;
          }
          Navigator.pop(
            context,
            _VendorStaffUpdate(
              role: roleChanged ? _role : null,
              active: statusChanged ? _active : null,
            ),
          );
        },
        child: const Text('Save'),
      ),
    ],
  );
}
