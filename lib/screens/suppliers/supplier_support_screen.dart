import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils.dart';
import '../../models/catalog.dart';
import '../../providers/admin_providers.dart';
import '../../widgets/common.dart';

final supplierSupportCasesProvider =
    FutureProvider.autoDispose<List<SupportCase>>(
      (ref) => ref.watch(platformServiceProvider).supportCases(),
    );

class SupplierSupportScreen extends ConsumerWidget {
  const SupplierSupportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cases = ref.watch(supplierSupportCasesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHead(
          eyebrow: 'SUPPORT',
          title: 'MVEC Support',
          subtitle: 'Contact the MVEC team and follow up on your support cases.',
          actions: [
            GradientButton(
              label: 'Open a support case',
              icon: 'plus',
              onPressed: () => _openCaseForm(context),
            ),
          ],
        ),
        const InfoBox(
          'Your cases are private to your account. The MVEC support team will review and respond to them.',
        ),
        const SizedBox(height: 16),
        switch (cases) {
          AsyncLoading() => const LoadingState(),
          AsyncError(:final error) => ErrorState(
            message: friendlyError(error),
            onRetry: () => ref.invalidate(supplierSupportCasesProvider),
          ),
          AsyncData(:final value) when value.isEmpty => const InfoBox(
            'You have not opened any support cases yet.',
            icon: 'bell',
          ),
          AsyncData(:final value) => _caseList(value),
          _ => const LoadingState(),
        },
      ],
    );
  }

  Widget _caseList(List<SupportCase> cases) => Column(
    children: [
      for (final supportCase in cases) ...[
        DataCard(
          title: supportCase.subject ?? 'Support case',
          subtitle: [
            if (supportCase.ticketNumber?.isNotEmpty == true)
              supportCase.ticketNumber!,
            if (supportCase.category?.isNotEmpty == true)
              titleCase(supportCase.category!),
            if (supportCase.createdAt != null)
              shortDate(supportCase.createdAt),
          ].join(' · '),
          trailing: StatusChip(supportCase.status),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              supportCase.message ?? 'No description provided.',
              style: const TextStyle(fontSize: 13, height: 1.45),
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
    ],
  );

  void _openCaseForm(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (_) => const _SupportCaseForm(),
    );
  }
}

class _SupportCaseForm extends ConsumerStatefulWidget {
  const _SupportCaseForm();

  @override
  ConsumerState<_SupportCaseForm> createState() => _SupportCaseFormState();
}

class _SupportCaseFormState extends ConsumerState<_SupportCaseForm> {
  final _subject = TextEditingController();
  final _description = TextEditingController();
  String _category = 'OTHER';
  String _priority = 'MEDIUM';
  bool _saving = false;

  @override
  void dispose() {
    _subject.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_subject.text.trim().isEmpty || _description.text.trim().isEmpty) {
      showMvSnack(context, 'Enter a subject and describe how we can help.');
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(platformServiceProvider).createSupportCase(
        subject: _subject.text.trim(),
        description: _description.text.trim(),
        category: _category,
        priority: _priority,
      );
      ref.invalidate(supplierSupportCasesProvider);
      if (mounted) {
        Navigator.pop(context);
        showMvSnack(context, 'Support case sent to MVEC.', success: true);
      }
    } catch (error) {
      if (mounted) showMvSnack(context, friendlyError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Open a support case',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _subject,
              decoration: const InputDecoration(labelText: 'Subject *'),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: const [
                DropdownMenuItem(value: 'OTHER', child: Text('Other')),
                DropdownMenuItem(value: 'ACCOUNT', child: Text('Account')),
                DropdownMenuItem(value: 'ORDERS', child: Text('Orders')),
                DropdownMenuItem(value: 'PAYMENTS', child: Text('Payments')),
                DropdownMenuItem(value: 'TECHNICAL', child: Text('Technical')),
              ],
              onChanged: _saving
                  ? null
                  : (value) {
                      if (value != null) setState(() => _category = value);
                    },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _priority,
              decoration: const InputDecoration(labelText: 'Priority'),
              items: const [
                DropdownMenuItem(value: 'LOW', child: Text('Low')),
                DropdownMenuItem(value: 'MEDIUM', child: Text('Medium')),
                DropdownMenuItem(value: 'HIGH', child: Text('High')),
              ],
              onChanged: _saving
                  ? null
                  : (value) {
                      if (value != null) setState(() => _priority = value);
                    },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'How can we help? *',
                alignLabelWithHint: true,
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 16),
            GradientButton(
              label: _saving ? 'Sending…' : 'Send to MVEC',
              icon: 'arrow',
              expanded: true,
              onPressed: _saving ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}
