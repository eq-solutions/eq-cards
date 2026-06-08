import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/error/user_messages.dart';
import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../../core/validators/input_validators.dart';
import '../../../../core/widgets/eq_app_bar.dart';
import '../../../../core/widgets/eq_button.dart';
import '../../../../core/widgets/eq_text_field.dart';
import '../../../auth/data/aus_phone.dart';
import '../../data/admin_worker_repository.dart';
import '../providers/org_admin_provider.dart';

/// Create or edit a worker profile.
///
/// Pass [worker] to edit an existing record; omit (or null) to create.
/// [orgId] is always required and comes via GoRouter's extra field.
class AdminWorkerFormScreen extends ConsumerStatefulWidget {
  const AdminWorkerFormScreen({super.key, this.worker, required this.orgId});

  final Worker? worker;
  final String orgId;

  @override
  ConsumerState<AdminWorkerFormScreen> createState() =>
      _AdminWorkerFormScreenState();
}

class _AdminWorkerFormScreenState
    extends ConsumerState<AdminWorkerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _preferredName = TextEditingController();

  String? _role;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final w = widget.worker;
    if (w != null) {
      _firstName.text = w.firstName;
      _lastName.text = w.lastName;
      _phone.text = w.phone ?? '';
      _email.text = w.email ?? '';
      _preferredName.text = w.preferredName ?? '';
      _role = w.role;
    }
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    _email.dispose();
    _preferredName.dispose();
    super.dispose();
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  String? _orNull(String text) {
    final t = text.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final repo = ref.read(adminWorkerRepositoryProvider);
      final existing = widget.worker;

      // Store the mobile in E.164 so it matches the claim-by-phone lookup
      // exactly. The required validator guarantees a normalisable value here;
      // fall back to the trimmed text only as a belt-and-braces measure.
      final normalisedPhone =
          normaliseAusMobile(_phone.text.trim()) ?? _phone.text.trim();

      final draft = existing != null
          ? existing.copyWith(
              firstName: _firstName.text.trim(),
              lastName: _lastName.text.trim(),
              phone: normalisedPhone,
              email: _orNull(_email.text),
              preferredName: _orNull(_preferredName.text),
              role: _role,
            )
          : Worker(
              id: '',
              firstName: _firstName.text.trim(),
              lastName: _lastName.text.trim(),
              phone: normalisedPhone,
              email: _orNull(_email.text),
              preferredName: _orNull(_preferredName.text),
              role: _role,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            );

      await repo.upsertWorker(
        widget.orgId,
        AdminWorkerRepository.workerToPayload(draft),
      );

      ref.invalidate(adminWorkersListProvider(widget.orgId));
      ref.invalidate(orgAdminOrgIdProvider);

      if (mounted) context.pop(true);
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
    final isEdit = widget.worker != null;

    return Scaffold(
      appBar: EqAppBar(title: isEdit ? 'Edit member' : 'Add member'),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(EqSpacing.md),
          children: [
            _SectionHeader('Name'),
            const SizedBox(height: EqSpacing.sm),
            EqTextField(
              controller: _firstName,
              label: 'First name',
              validator: _required,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: EqSpacing.sm),
            EqTextField(
              controller: _lastName,
              label: 'Last name',
              validator: _required,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: EqSpacing.sm),
            EqTextField(
              controller: _preferredName,
              label: 'Preferred name (optional)',
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: EqSpacing.lg),
            _SectionHeader('Role'),
            const SizedBox(height: EqSpacing.xs),
            Text(
              'Applied when the worker activates their account. '
              'Leave unset to default to Employee.',
              style: EqTypography.label.copyWith(color: EqColours.grey),
            ),
            const SizedBox(height: EqSpacing.sm),
            // Plain DropdownButton (not DropdownButtonFormField) to match the
            // codebase convention — the FormField variant carries a late-init
            // hazard (#EQ-CARDS-B). _role is tracked in screen state.
            DropdownButtonHideUnderline(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: EqSpacing.md,
                  vertical: EqSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: EqColours.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButton<String?>(
                  value: _role,
                  isExpanded: true,
                  isDense: true,
                  underline: const SizedBox.shrink(),
                  style: EqTypography.bodyM.copyWith(color: EqColours.ink),
                  dropdownColor: EqColours.white,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Not set'),
                    ),
                    for (final entry in kEqRoleLabels.entries)
                      DropdownMenuItem<String?>(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged:
                      _saving ? null : (v) => setState(() => _role = v),
                ),
              ),
            ),
            const SizedBox(height: EqSpacing.lg),
            _SectionHeader('Contact'),
            const SizedBox(height: EqSpacing.xs),
            Text(
              'The mobile number is how the worker activates their account, '
              'so it must be correct.',
              style: EqTypography.label.copyWith(color: EqColours.grey),
            ),
            const SizedBox(height: EqSpacing.sm),
            EqTextField(
              controller: _phone,
              label: 'Mobile number',
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              validator: validateMobileRequired,
            ),
            const SizedBox(height: EqSpacing.sm),
            EqTextField(
              controller: _email,
              label: 'Email (optional)',
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              onEditingComplete: _save,
            ),
            const SizedBox(height: EqSpacing.xl),
            EqButton(
              label: isEdit ? 'Save changes' : 'Create profile',
              onPressed: _saving ? null : _save,
              isLoading: _saving,
              fullWidth: true,
            ),
            const SizedBox(height: EqSpacing.md),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: EqSpacing.xs),
      child: Text(text, style: EqTypography.label),
    );
  }
}
