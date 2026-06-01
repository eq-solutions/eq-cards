import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/error/user_messages.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../../core/widgets/eq_app_bar.dart';
import '../../../../core/widgets/eq_button.dart';
import '../../../../core/widgets/eq_card.dart';
import '../../../../core/widgets/eq_text_field.dart';
import '../../data/admin_worker_repository.dart';
import '../../data/models/worker.dart';
import '../../data/models/worker_invite.dart';
import '../../../worker_house/data/models/worker_credential.dart';

class AdminWorkerDetailScreen extends ConsumerWidget {
  const AdminWorkerDetailScreen({
    super.key,
    required this.workerId,
    required this.orgId,
  });

  final String workerId;
  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workersAsync = ref.watch(adminWorkersListProvider(orgId));
    final credsAsync = ref.watch(adminWorkerCredentialsProvider(workerId));
    final invitesAsync = ref.watch(adminWorkerInvitesProvider(orgId));

    final worker = workersAsync.value?.where((w) => w.id == workerId).firstOrNull;

    if (worker == null && workersAsync.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: EqColours.sky)),
      );
    }
    if (worker == null) {
      return Scaffold(
        appBar: const EqAppBar(title: 'Member'),
        body: const Center(child: Text('Member not found.')),
      );
    }

    final activeInvite = invitesAsync.value
        ?.where((i) => i.workerId == workerId && i.isActive)
        .firstOrNull;

    return Scaffold(
      appBar: EqAppBar(
        title: worker.displayName,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: () => context.push(
              Routes.adminMemberEditFor(workerId),
              extra: (orgId, worker),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: EqColours.sky,
        onRefresh: () async {
          ref.invalidate(adminWorkersListProvider(orgId));
          ref.invalidate(adminWorkerCredentialsProvider(workerId));
          ref.invalidate(adminWorkerInvitesProvider(orgId));
        },
        child: ListView(
          padding: const EdgeInsets.all(EqSpacing.md),
          children: [
            // ── Profile summary ─────────────────────────────────────────
            EqCard(
              padding: const EdgeInsets.all(EqSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow('Status', worker.isClaimed ? 'Active' : 'Pending invite'),
                  if (worker.phone != null)
                    _InfoRow('Mobile', worker.phone!),
                  if (worker.email != null)
                    _InfoRow('Email', worker.email!),
                ],
              ),
            ),
            const SizedBox(height: EqSpacing.lg),

            // ── Invite section ───────────────────────────────────────────
            if (!worker.isClaimed) ...[
              Padding(
                padding: const EdgeInsets.only(left: EqSpacing.xs, bottom: EqSpacing.sm),
                child: Text('Invite', style: EqTypography.label),
              ),
              if (activeInvite != null)
                _ActiveInviteCard(invite: activeInvite, orgId: orgId)
              else
                _SendInviteCard(worker: worker, orgId: orgId),
              const SizedBox(height: EqSpacing.lg),
            ],

            // ── Credentials ──────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: EqSpacing.xs),
                    child: Text('Credentials', style: EqTypography.label),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _showAddCredentialSheet(context, ref),
                  icon: const Icon(Icons.add, size: 18, color: EqColours.sky),
                  label: Text(
                    'Add',
                    style: EqTypography.bodyM.copyWith(color: EqColours.sky),
                  ),
                ),
              ],
            ),
            const SizedBox(height: EqSpacing.sm),
            credsAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(EqSpacing.md),
                  child: CircularProgressIndicator(color: EqColours.sky),
                ),
              ),
              error: (_, __) => Text(
                'Could not load credentials.',
                style: EqTypography.bodyM.copyWith(color: EqColours.grey),
              ),
              data: (creds) {
                if (creds.isEmpty) {
                  return EqCard(
                    padding: const EdgeInsets.all(EqSpacing.md),
                    child: Text(
                      'No credentials yet. Tap "Add" to enter licences and tickets.',
                      style: EqTypography.bodyM.copyWith(color: EqColours.grey),
                    ),
                  );
                }
                return Column(
                  children: creds
                      .map((c) => Padding(
                            padding:
                                const EdgeInsets.only(bottom: EqSpacing.sm),
                            child: _CredentialTile(credential: c),
                          ))
                      .toList(),
                );
              },
            ),
            const SizedBox(height: EqSpacing.xl),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddCredentialSheet(
      BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: EqColours.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _AddCredentialSheet(
        workerId: workerId,
        orgId: orgId,
        onSaved: () {
          ref.invalidate(adminWorkerCredentialsProvider(workerId));
        },
      ),
    );
  }
}

// ── Info row ─────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: EqSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(label, style: EqTypography.label),
          ),
          Expanded(child: Text(value, style: EqTypography.bodyM)),
        ],
      ),
    );
  }
}

// ── Invite cards ─────────────────────────────────────────────────────────────

class _SendInviteCard extends ConsumerStatefulWidget {
  const _SendInviteCard({required this.worker, required this.orgId});

  final Worker worker;
  final String orgId;

  @override
  ConsumerState<_SendInviteCard> createState() => _SendInviteCardState();
}

class _SendInviteCardState extends ConsumerState<_SendInviteCard> {
  bool _loading = false;

  Future<void> _generate() async {
    setState(() => _loading = true);
    try {
      await ref
          .read(adminWorkerRepositoryProvider)
          .createInvite(widget.orgId, widget.worker.id);
      ref.invalidate(adminWorkerInvitesProvider(widget.orgId));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userMessageForError(e)),
          backgroundColor: EqColours.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return EqCard(
      padding: const EdgeInsets.all(EqSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No active invite.',
            style: EqTypography.bodyM.copyWith(color: EqColours.grey),
          ),
          const SizedBox(height: EqSpacing.md),
          EqButton(
            label: 'Generate invite link',
            onPressed: _loading ? null : _generate,
            isLoading: _loading,
            fullWidth: true,
          ),
        ],
      ),
    );
  }
}

class _ActiveInviteCard extends ConsumerStatefulWidget {
  const _ActiveInviteCard({required this.invite, required this.orgId});

  final WorkerInvite invite;
  final String orgId;

  @override
  ConsumerState<_ActiveInviteCard> createState() => _ActiveInviteCardState();
}

class _ActiveInviteCardState extends ConsumerState<_ActiveInviteCard> {
  bool _revoking = false;

  String get _claimUrl =>
      'https://cards.eq.solutions/claim?token=${widget.invite.token}';

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _claimUrl));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Invite link copied — paste it into a text message.'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: EqColours.ink,
      ),
    );
  }

  Future<void> _revoke() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke invite?'),
        content: const Text('The worker won\'t be able to use this link. '
            'You can generate a new one.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Revoke',
                  style: TextStyle(color: EqColours.error))),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _revoking = true);
    try {
      await ref
          .read(adminWorkerRepositoryProvider)
          .revokeInvite(widget.invite.id);
      ref.invalidate(adminWorkerInvitesProvider(widget.orgId));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userMessageForError(e)),
          backgroundColor: EqColours.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _revoking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final days =
        widget.invite.expiresAt.difference(DateTime.now()).inDays.clamp(0, 99);

    return EqCard(
      padding: const EdgeInsets.all(EqSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.link, color: EqColours.sky, size: 18),
              const SizedBox(width: EqSpacing.sm),
              Expanded(
                child: Text(
                  'Active invite — expires in $days day${days == 1 ? '' : 's'}',
                  style: EqTypography.bodyM,
                ),
              ),
            ],
          ),
          const SizedBox(height: EqSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: EqSpacing.sm, vertical: EqSpacing.xs),
            decoration: BoxDecoration(
              color: EqColours.ice,
              borderRadius: BorderRadius.circular(6),
            ),
            child: SelectableText(
              _claimUrl,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          const SizedBox(height: EqSpacing.md),
          Row(
            children: [
              Expanded(
                child: EqButton(
                  label: 'Copy link',
                  onPressed: _copy,
                ),
              ),
              const SizedBox(width: EqSpacing.sm),
              EqButton(
                label: 'Revoke',
                variant: EqButtonVariant.destructive,
                onPressed: _revoking ? null : _revoke,
                isLoading: _revoking,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Credential tile ──────────────────────────────────────────────────────────

class _CredentialTile extends StatelessWidget {
  const _CredentialTile({required this.credential});

  final WorkerCredential credential;

  String get _label =>
      workerCredentialTypeLabels[credential.credentialType] ??
      credential.credentialType;

  Color get _statusColour {
    if (credential.isExpired) return EqColours.error;
    if (credential.isExpiringSoon) return EqColours.warning;
    return EqColours.success;
  }

  @override
  Widget build(BuildContext context) {
    return EqCard(
      padding: const EdgeInsets.all(EqSpacing.md),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: _statusColour,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: EqSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_label, style: EqTypography.bodyL),
                if (credential.expiryDate != null) ...[
                  const SizedBox(height: EqSpacing.xs),
                  Text(
                    credential.isExpired
                        ? 'Expired'
                        : 'Expires ${_formatDate(credential.expiryDate!)}',
                    style: EqTypography.label.copyWith(color: _statusColour),
                  ),
                ] else
                  Text('No expiry', style: EqTypography.label),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

// ── Add credential sheet ─────────────────────────────────────────────────────

class _AddCredentialSheet extends ConsumerStatefulWidget {
  const _AddCredentialSheet({
    required this.workerId,
    required this.orgId,
    required this.onSaved,
  });

  final String workerId;
  final String orgId;
  final VoidCallback onSaved;

  @override
  ConsumerState<_AddCredentialSheet> createState() =>
      _AddCredentialSheetState();
}

class _AddCredentialSheetState extends ConsumerState<_AddCredentialSheet> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedType;
  final _licenceNumber = TextEditingController();
  final _issuingBody = TextEditingController();
  DateTime? _expiryDate;
  bool _saving = false;

  final _credentialTypes = workerCredentialTypeLabels.entries
      .where((e) => e.key != 'other')
      .toList()
    ..sort((a, b) => a.value.compareTo(b.value));

  @override
  void dispose() {
    _licenceNumber.dispose();
    _issuingBody.dispose();
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime(2000),
      lastDate: DateTime(2050),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme:
              const ColorScheme.light(primary: EqColours.sky),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _expiryDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedType == null) return;

    setState(() => _saving = true);
    try {
      final payload = {
        'credential_type': _selectedType,
        if (_licenceNumber.text.trim().isNotEmpty)
          'licence_number': _licenceNumber.text.trim(),
        if (_issuingBody.text.trim().isNotEmpty)
          'issuing_body': _issuingBody.text.trim(),
        if (_expiryDate != null)
          'expiry_date':
              '${_expiryDate!.year}-${_expiryDate!.month.toString().padLeft(2, '0')}-${_expiryDate!.day.toString().padLeft(2, '0')}',
      };
      await ref
          .read(adminWorkerRepositoryProvider)
          .upsertCredential(widget.orgId, widget.workerId, payload);
      widget.onSaved();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userMessageForError(e)),
          backgroundColor: EqColours.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          EqSpacing.md, EqSpacing.lg, EqSpacing.md, EqSpacing.md + bottom),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add credential', style: EqTypography.headingM),
            const SizedBox(height: EqSpacing.md),
            DropdownButtonFormField<String>(
              value: _selectedType,
              decoration: const InputDecoration(
                labelText: 'Credential type',
                border: OutlineInputBorder(),
              ),
              items: _credentialTypes
                  .map((e) => DropdownMenuItem(
                      value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedType = v),
              validator: (v) =>
                  v == null ? 'Select a credential type' : null,
            ),
            const SizedBox(height: EqSpacing.sm),
            EqTextField(
              controller: _licenceNumber,
              label: 'Licence / ticket number (optional)',
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: EqSpacing.sm),
            EqTextField(
              controller: _issuingBody,
              label: 'Issuing body (optional)',
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: EqSpacing.sm),
            InkWell(
              onTap: _pickExpiry,
              borderRadius: BorderRadius.circular(4),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Expiry date (optional)',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.calendar_today_outlined),
                ),
                child: Text(
                  _expiryDate == null
                      ? 'No expiry'
                      : '${_expiryDate!.day}/${_expiryDate!.month}/${_expiryDate!.year}',
                  style: EqTypography.bodyM,
                ),
              ),
            ),
            const SizedBox(height: EqSpacing.md),
            EqButton(
              label: 'Save credential',
              onPressed: _saving ? null : _save,
              isLoading: _saving,
              fullWidth: true,
            ),
          ],
        ),
      ),
    );
  }
}
