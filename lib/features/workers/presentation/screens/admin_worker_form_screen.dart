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

  // ── Identity ───────────────────────────────────────────────────────────────
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _preferredName = TextEditingController();
  String? _role;

  // ── Contact ────────────────────────────────────────────────────────────────
  final _phone = TextEditingController();
  final _email = TextEditingController();

  // ── Date of birth ──────────────────────────────────────────────────────────
  DateTime? _dateOfBirth;

  // ── Address ────────────────────────────────────────────────────────────────
  final _addressStreet = TextEditingController();
  final _addressSuburb = TextEditingController();
  String? _addressState;
  final _addressPostcode = TextEditingController();

  // ── Emergency contact ──────────────────────────────────────────────────────
  final _emergencyName = TextEditingController();
  final _emergencyPhone = TextEditingController();
  final _emergencyRelationship = TextEditingController();

  // ── Right to work ──────────────────────────────────────────────────────────
  String? _rightToWorkType;
  DateTime? _rightToWorkExpiry;

  bool _saving = false;

  static const _auStates = ['ACT', 'NSW', 'NT', 'QLD', 'SA', 'TAS', 'VIC', 'WA'];

  static const _rightToWorkOptions = {
    'citizen': 'Australian / NZ Citizen',
    'permanent_resident': 'Permanent Resident',
    'visa': 'Visa Holder',
    'working_holiday': 'Working Holiday',
  };

  @override
  void initState() {
    super.initState();
    final w = widget.worker;
    if (w != null) {
      _firstName.text = w.firstName;
      _lastName.text = w.lastName;
      _preferredName.text = w.preferredName ?? '';
      _role = w.role;
      _phone.text = w.phone ?? '';
      _email.text = w.email ?? '';
      _dateOfBirth = w.dateOfBirth;
      _addressStreet.text = w.addressStreet ?? '';
      _addressSuburb.text = w.addressSuburb ?? '';
      _addressState = w.addressState;
      _addressPostcode.text = w.addressPostcode ?? '';
      _emergencyName.text = w.emergencyContactName ?? '';
      _emergencyPhone.text = w.emergencyContactPhone ?? '';
      _emergencyRelationship.text = w.emergencyContactRelationship ?? '';
      _rightToWorkType = w.rightToWorkType;
      _rightToWorkExpiry = w.rightToWorkExpiry;
    }
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _preferredName.dispose();
    _phone.dispose();
    _email.dispose();
    _addressStreet.dispose();
    _addressSuburb.dispose();
    _addressPostcode.dispose();
    _emergencyName.dispose();
    _emergencyPhone.dispose();
    _emergencyRelationship.dispose();
    super.dispose();
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  String? _orNull(String text) {
    final t = text.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _pickDate({
    required DateTime? current,
    required DateTime firstDate,
    required DateTime lastDate,
    required ValueChanged<DateTime> onPicked,
  }) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? lastDate,
      firstDate: firstDate,
      lastDate: lastDate,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: EqColours.sky),
        ),
        child: child!,
      ),
    );
    if (picked != null) onPicked(picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final repo = ref.read(adminWorkerRepositoryProvider);
      final existing = widget.worker;

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
              dateOfBirth: _dateOfBirth,
              addressStreet: _orNull(_addressStreet.text),
              addressSuburb: _orNull(_addressSuburb.text),
              addressState: _addressState,
              addressPostcode: _orNull(_addressPostcode.text),
              emergencyContactName: _orNull(_emergencyName.text),
              emergencyContactPhone: _orNull(_emergencyPhone.text),
              emergencyContactRelationship: _orNull(_emergencyRelationship.text),
              rightToWorkType: _rightToWorkType,
              rightToWorkExpiry: _rightToWorkExpiry,
            )
          : Worker(
              id: '',
              firstName: _firstName.text.trim(),
              lastName: _lastName.text.trim(),
              phone: normalisedPhone,
              email: _orNull(_email.text),
              preferredName: _orNull(_preferredName.text),
              role: _role,
              dateOfBirth: _dateOfBirth,
              addressStreet: _orNull(_addressStreet.text),
              addressSuburb: _orNull(_addressSuburb.text),
              addressState: _addressState,
              addressPostcode: _orNull(_addressPostcode.text),
              emergencyContactName: _orNull(_emergencyName.text),
              emergencyContactPhone: _orNull(_emergencyPhone.text),
              emergencyContactRelationship: _orNull(_emergencyRelationship.text),
              rightToWorkType: _rightToWorkType,
              rightToWorkExpiry: _rightToWorkExpiry,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            );

      await repo.upsertWorker(
        widget.orgId,
        AdminWorkerRepository.workerToPayload(draft),
      );

      ref.invalidate(adminWorkersListProvider(widget.orgId));

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
    final needsExpiry =
        _rightToWorkType == 'visa' || _rightToWorkType == 'working_holiday';

    return Scaffold(
      appBar: EqAppBar(title: isEdit ? 'Edit member' : 'Add member'),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(EqSpacing.md),
          children: [

            // ── Name ─────────────────────────────────────────────────────────
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

            // ── Role ─────────────────────────────────────────────────────────
            const SizedBox(height: EqSpacing.lg),
            _SectionHeader('Role'),
            const SizedBox(height: EqSpacing.xs),
            Text(
              'Applied when the worker activates their account. '
              'Leave unset to default to Employee.',
              style: EqTypography.label.copyWith(color: EqColours.grey),
            ),
            const SizedBox(height: EqSpacing.sm),
            _DropdownRow<String?>(
              value: _role,
              hint: 'Not set',
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Not set')),
                for (final entry in kEqRoleLabels.entries)
                  DropdownMenuItem<String?>(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: _saving ? null : (v) => setState(() => _role = v),
            ),

            // ── Contact ───────────────────────────────────────────────────────
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
              textInputAction: TextInputAction.next,
            ),

            // ── Date of birth ─────────────────────────────────────────────────
            const SizedBox(height: EqSpacing.lg),
            _SectionHeader('Date of birth'),
            const SizedBox(height: EqSpacing.sm),
            _DatePickerRow(
              label: _dateOfBirth != null
                  ? '${_dateOfBirth!.day.toString().padLeft(2, '0')} / '
                    '${_dateOfBirth!.month.toString().padLeft(2, '0')} / '
                    '${_dateOfBirth!.year}'
                  : 'Not set',
              onTap: _saving
                  ? null
                  : () => _pickDate(
                        current: _dateOfBirth,
                        firstDate: DateTime(1930),
                        lastDate: DateTime.now().subtract(
                          const Duration(days: 365 * 15),
                        ),
                        onPicked: (d) => setState(() => _dateOfBirth = d),
                      ),
            ),

            // ── Address ───────────────────────────────────────────────────────
            const SizedBox(height: EqSpacing.lg),
            _SectionHeader('Address'),
            const SizedBox(height: EqSpacing.sm),
            EqTextField(
              controller: _addressStreet,
              label: 'Street address (optional)',
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: EqSpacing.sm),
            EqTextField(
              controller: _addressSuburb,
              label: 'Suburb (optional)',
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: EqSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: _DropdownRow<String?>(
                    value: _addressState,
                    hint: 'State',
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('State')),
                      for (final s in _auStates)
                        DropdownMenuItem<String?>(value: s, child: Text(s)),
                    ],
                    onChanged: _saving ? null : (v) => setState(() => _addressState = v),
                  ),
                ),
                const SizedBox(width: EqSpacing.sm),
                Expanded(
                  flex: 3,
                  child: EqTextField(
                    controller: _addressPostcode,
                    label: 'Postcode (optional)',
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                  ),
                ),
              ],
            ),

            // ── Emergency contact ─────────────────────────────────────────────
            const SizedBox(height: EqSpacing.lg),
            _SectionHeader('Emergency contact'),
            const SizedBox(height: EqSpacing.sm),
            EqTextField(
              controller: _emergencyName,
              label: 'Name (optional)',
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: EqSpacing.sm),
            EqTextField(
              controller: _emergencyPhone,
              label: 'Phone (optional)',
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: EqSpacing.sm),
            EqTextField(
              controller: _emergencyRelationship,
              label: 'Relationship (optional)',
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
            ),

            // ── Right to work ─────────────────────────────────────────────────
            const SizedBox(height: EqSpacing.lg),
            _SectionHeader('Right to work'),
            const SizedBox(height: EqSpacing.sm),
            _DropdownRow<String?>(
              value: _rightToWorkType,
              hint: 'Not set',
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Not set')),
                for (final entry in _rightToWorkOptions.entries)
                  DropdownMenuItem<String?>(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: _saving
                  ? null
                  : (v) => setState(() {
                        _rightToWorkType = v;
                        if (v == 'citizen' || v == 'permanent_resident') {
                          _rightToWorkExpiry = null;
                        }
                      }),
            ),
            if (needsExpiry) ...[
              const SizedBox(height: EqSpacing.sm),
              _DatePickerRow(
                label: _rightToWorkExpiry != null
                    ? '${_rightToWorkExpiry!.day.toString().padLeft(2, '0')} / '
                      '${_rightToWorkExpiry!.month.toString().padLeft(2, '0')} / '
                      '${_rightToWorkExpiry!.year}'
                    : 'Visa expiry — tap to set',
                onTap: _saving
                    ? null
                    : () => _pickDate(
                          current: _rightToWorkExpiry,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365 * 10),
                          ),
                          onPicked: (d) => setState(() => _rightToWorkExpiry = d),
                        ),
              ),
            ],

            // ── Save ──────────────────────────────────────────────────────────
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

// ── Shared widgets ────────────────────────────────────────────────────────────

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

class _DropdownRow<T> extends StatelessWidget {
  const _DropdownRow({
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final String hint;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: EqSpacing.md,
          vertical: EqSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: EqColours.surface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          isDense: true,
          underline: const SizedBox.shrink(),
          style: EqTypography.bodyM.copyWith(color: EqColours.ink),
          dropdownColor: EqColours.white,
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _DatePickerRow extends StatelessWidget {
  const _DatePickerRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: EqSpacing.md,
          vertical: EqSpacing.md,
        ),
        decoration: BoxDecoration(
          color: EqColours.surface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_outlined,
                size: 18, color: EqColours.grey),
            const SizedBox(width: EqSpacing.sm),
            Text(label, style: EqTypography.bodyM.copyWith(color: EqColours.ink)),
          ],
        ),
      ),
    );
  }
}
