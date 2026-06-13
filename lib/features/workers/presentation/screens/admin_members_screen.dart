import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../../core/widgets/eq_app_bar.dart';
import '../../../../core/widgets/eq_card.dart';
import '../../data/access_request_repository.dart';
import '../../data/admin_worker_repository.dart';
import '../providers/org_admin_provider.dart';

class AdminMembersScreen extends ConsumerWidget {
  const AdminMembersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orgAsync = ref.watch(orgAdminOrgIdProvider);

    return orgAsync.when(
      loading: () => const Scaffold(
        appBar: PreferredSize(
          preferredSize: Size.fromHeight(kToolbarHeight),
          child: EqAppBar(title: 'Team'),
        ),
        body: Center(child: CircularProgressIndicator(color: EqColours.sky)),
      ),
      error: (e, s) => const Scaffold(
        appBar: PreferredSize(
          preferredSize: Size.fromHeight(kToolbarHeight),
          child: EqAppBar(title: 'Team'),
        ),
        body: Center(child: Text('Unable to load team.')),
      ),
      data: (orgId) {
        if (orgId == null) {
          return Scaffold(
            appBar: const EqAppBar(title: 'Team'),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(EqSpacing.lg),
                child: Text(
                  'You are not set up as an org admin.',
                  style: EqTypography.bodyM.copyWith(color: EqColours.grey),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        return _MemberList(orgId: orgId);
      },
    );
  }
}

class _MemberList extends ConsumerWidget {
  const _MemberList({required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workersAsync = ref.watch(adminWorkersListProvider(orgId));

    return Scaffold(
      appBar: EqAppBar(
        title: 'Team',
        actions: [
          IconButton(
            icon: const Icon(Icons.person_search_outlined),
            tooltip: 'Request access',
            onPressed: () => _showRequestAccess(context, orgId),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(adminWorkersListProvider(orgId)),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.adminMemberNew, extra: orgId),
        backgroundColor: EqColours.sky,
        foregroundColor: EqColours.white,
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Add member'),
      ),
      body: workersAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: EqColours.sky)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(EqSpacing.lg),
            child: Text(
              'Could not load team members.',
              style: EqTypography.bodyM.copyWith(color: EqColours.grey),
            ),
          ),
        ),
        data: (workers) {
          if (workers.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(EqSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.group_outlined,
                        size: 56, color: EqColours.grey),
                    const SizedBox(height: EqSpacing.md),
                    Text('No team members yet',
                        style: EqTypography.headingM
                            .copyWith(color: EqColours.ink)),
                    const SizedBox(height: EqSpacing.sm),
                    Text(
                      'Tap "Add member" to create a profile\nand send an invite link.',
                      style:
                          EqTypography.bodyM.copyWith(color: EqColours.grey),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          return RefreshIndicator(
            color: EqColours.sky,
            onRefresh: () async =>
                ref.invalidate(adminWorkersListProvider(orgId)),
            child: ListView.separated(
              padding: const EdgeInsets.all(EqSpacing.md),
              itemCount: workers.length,
              separatorBuilder: (_, i) =>
                  const SizedBox(height: EqSpacing.sm),
              itemBuilder: (_, i) => _WorkerTile(
                worker: workers[i],
                onTap: () => context.push(
                  Routes.adminMemberDetailFor(workers[i].id),
                  extra: orgId,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _WorkerTile extends StatelessWidget {
  const _WorkerTile({required this.worker, required this.onTap});

  final Worker worker;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return EqCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(EqSpacing.md),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: EqColours.surface,
                child: Text(
                  worker.firstName.isNotEmpty
                      ? worker.firstName[0].toUpperCase()
                      : '?',
                  style: EqTypography.bodyL
                      .copyWith(color: EqColours.deep, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: EqSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(worker.displayName, style: EqTypography.bodyL),
                    if (worker.role != null) ...[
                      const SizedBox(height: EqSpacing.xs),
                      Text(
                        kEqRoleLabels[worker.role] ?? worker.role!,
                        style: EqTypography.label.copyWith(
                          color: EqColours.deep,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (worker.phone != null) ...[
                      const SizedBox(height: EqSpacing.xs),
                      Text(worker.phone!, style: EqTypography.label),
                    ],
                  ],
                ),
              ),
              _StatusChip(isClaimed: worker.isClaimed),
              const SizedBox(width: EqSpacing.sm),
              const Icon(Icons.chevron_right, color: EqColours.grey),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showRequestAccess(BuildContext context, String orgId) async {
  final sent = await showDialog<bool>(
    context: context,
    builder: (_) => _RequestAccessDialog(orgId: orgId),
  );
  if (sent == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "Request sent. They'll see it next time they open EQ Cards.",
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: EqColours.ink,
      ),
    );
  }
}

/// Admin dialog: ask an existing tradie (by mobile) to connect their wallet.
class _RequestAccessDialog extends ConsumerStatefulWidget {
  const _RequestAccessDialog({required this.orgId});

  final String orgId;

  @override
  ConsumerState<_RequestAccessDialog> createState() =>
      _RequestAccessDialogState();
}

class _RequestAccessDialogState extends ConsumerState<_RequestAccessDialog> {
  final _phone = TextEditingController();
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final phone = _phone.text.trim();
    if (phone.isEmpty) {
      setState(() => _error = 'Enter their mobile number.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(accessRequestRepositoryProvider).requestWorkerAccess(
            widget.orgId,
            phone,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      final s = e.toString();
      setState(() {
        _busy = false;
        _error = s.contains('already_member')
            ? 'That worker is already on your team.'
            : s.contains('invalid_phone')
                ? 'Enter a valid mobile number.'
                : 'Could not send the request. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Request access'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ask a tradie who already has an EQ Cards wallet to connect it to '
            "your team. They'll approve it on their phone.",
            style: EqTypography.label.copyWith(color: EqColours.grey),
          ),
          const SizedBox(height: EqSpacing.md),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            autocorrect: false,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'Mobile number',
              hintText: '04xx xxx xxx',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: EqSpacing.sm),
          TextField(
            controller: _note,
            enabled: !_busy,
            maxLength: 120,
            decoration: const InputDecoration(
              labelText: 'Message (optional)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: EqSpacing.xs),
            Text(
              _error!,
              style: EqTypography.label.copyWith(color: EqColours.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _send,
          style: FilledButton.styleFrom(backgroundColor: EqColours.sky),
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text('Send request'),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.isClaimed});

  final bool isClaimed;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = isClaimed
        ? ('Active', EqColours.success.withValues(alpha: 0.12), EqColours.success)
        : ('Pending', EqColours.warning.withValues(alpha: 0.12), EqColours.warning);

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: EqSpacing.sm, vertical: EqSpacing.xs),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: EqTypography.label.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
