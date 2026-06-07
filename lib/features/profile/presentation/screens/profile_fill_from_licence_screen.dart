import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/analytics/analytics_service.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../../core/widgets/eq_app_bar.dart';
import '../../../../core/widgets/eq_button.dart';
import '../../../../core/widgets/eq_text_field.dart';
import '../../../licences/presentation/screens/licence_edit_screen.dart'
    show LicencePrefill;
import '../../data/models/profile.dart';
import '../notifiers/profile_notifier.dart';

// ---------------------------------------------------------------------------
// Data carrier — passed as GoRouter `extra` from the capture flow.
// Holds the OCR-extracted driver licence profile fields plus the licence
// prefill to continue to after the user confirms their details.
// ---------------------------------------------------------------------------

class DlProfileFill {
  const DlProfileFill({
    this.holderName,
    this.dateOfBirth,
    this.addressStreet,
    this.addressSuburb,
    this.addressState,
    this.addressPostcode,
    required this.licencePrefill,
  });

  final String? holderName;
  final DateTime? dateOfBirth;
  final String? addressStreet;
  final String? addressSuburb;
  final String? addressState;
  final String? addressPostcode;

  /// Passed through to LicenceEditScreen after the profile save so the
  /// driver licence itself is still saved in the wallet.
  final LicencePrefill licencePrefill;
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/// Shown when a driver licence scan extracts name, DOB and/or address.
/// Pre-fills those fields for the user to review and confirm before saving
/// to their profile. After saving, continues to LicenceEditScreen so the
/// driver licence is also saved in the wallet.
class ProfileFillFromLicenceScreen extends ConsumerStatefulWidget {
  const ProfileFillFromLicenceScreen({super.key, this.fill});

  final DlProfileFill? fill;

  @override
  ConsumerState<ProfileFillFromLicenceScreen> createState() =>
      _ProfileFillFromLicenceScreenState();
}

class _ProfileFillFromLicenceScreenState
    extends ConsumerState<ProfileFillFromLicenceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _street = TextEditingController();
  final _suburb = TextEditingController();
  final _state = TextEditingController();
  final _postcode = TextEditingController();

  DateTime? _dateOfBirth;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final fill = widget.fill;
    if (fill != null) {
      _fullName.text = fill.holderName ?? '';
      _street.text = fill.addressStreet ?? '';
      _suburb.text = fill.addressSuburb ?? '';
      _state.text = fill.addressState ?? '';
      _postcode.text = fill.addressPostcode ?? '';
      _dateOfBirth = fill.dateOfBirth;
    }
  }

  @override
  void dispose() {
    _fullName.dispose();
    _street.dispose();
    _suburb.dispose();
    _state.dispose();
    _postcode.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final initial = _dateOfBirth ?? DateTime(now.year - 30);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1920),
      lastDate: now,
    );
    if (picked != null) setState(() => _dateOfBirth = picked);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      setState(() {
        _saving = false;
        _error = 'Your session has expired. Please sign in again.';
      });
      return;
    }

    // Build a Profile with only the fields from this screen — the repository
    // upsert skips null fields, so mobile, email and emergency contact are
    // left unchanged in the database.
    final draft = Profile(
      id: userId,
      fullName: _textOrNull(_fullName.text),
      dateOfBirth: _dateOfBirth,
      addressStreet: _textOrNull(_street.text),
      addressSuburb: _textOrNull(_suburb.text),
      addressState: _textOrNull(_state.text),
      addressPostcode: _textOrNull(_postcode.text),
    );

    try {
      await ref.read(profileNotifierProvider.notifier).save(draft);

      unawaited(
        AnalyticsService.track(
          'profile_filled_from_licence',
          {
            'has_name': draft.fullName != null,
            'has_dob': draft.dateOfBirth != null,
            'has_address': draft.addressStreet != null,
          },
        ),
      );

      if (!mounted) return;
      // Continue to the licence edit screen so the DL is also saved.
      context.go(
        Routes.licenceCreate,
        extra: widget.fill?.licencePrefill,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save your details. Check your connection and try again.';
        });
      }
    }
  }

  Future<void> _skip() async {
    // User doesn't want to save profile fields — go straight to licence save.
    if (!mounted) return;
    context.go(Routes.licenceCreate, extra: widget.fill?.licencePrefill);
  }

  String? _textOrNull(String value) {
    final t = value.trim();
    return t.isEmpty ? null : t;
  }

  @override
  Widget build(BuildContext context) {
    final dobLabel = _dateOfBirth == null
        ? 'Select date of birth'
        : DateFormat('d MMM yyyy').format(_dateOfBirth!);

    void onEnter() {
      if (!_saving) unawaited(_save());
    }

    return Scaffold(
      appBar: const EqAppBar(title: 'Your details'),
      body: SafeArea(
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.enter): onEnter,
            const SingleActivator(LogicalKeyboardKey.numpadEnter): onEnter,
          },
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(EqSpacing.md),
              children: [
                // --- Context banner -------------------------------------------
                Container(
                  padding: const EdgeInsets.all(EqSpacing.md),
                  decoration: BoxDecoration(
                    color: EqColours.surface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        color: EqColours.sky,
                        size: 18,
                      ),
                      const SizedBox(width: EqSpacing.sm),
                      Expanded(
                        child: Text(
                          'We read these details from your licence — '
                          'check they look right before saving.',
                          style: EqTypography.bodyM.copyWith(
                            color: EqColours.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: EqSpacing.lg),

                // --- Name & DOB -----------------------------------------------
                _SectionLabel('Your name'),
                EqTextField(
                  controller: _fullName,
                  label: 'Full name',
                ),
                const SizedBox(height: EqSpacing.md),
                InkWell(
                  onTap: _pickDob,
                  borderRadius: BorderRadius.circular(6),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Date of birth',
                      filled: true,
                      fillColor: EqColours.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    child: Text(dobLabel, style: EqTypography.bodyL),
                  ),
                ),
                const SizedBox(height: EqSpacing.lg),

                // --- Address --------------------------------------------------
                _SectionLabel('Address'),
                EqTextField(controller: _street, label: 'Street'),
                const SizedBox(height: EqSpacing.md),
                EqTextField(controller: _suburb, label: 'Suburb'),
                const SizedBox(height: EqSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: EqTextField(
                        controller: _state,
                        label: 'State',
                      ),
                    ),
                    const SizedBox(width: EqSpacing.md),
                    Expanded(
                      child: EqTextField(
                        controller: _postcode,
                        label: 'Postcode',
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: EqSpacing.xl),

                // --- Error message --------------------------------------------
                if (_error != null) ...[
                  Text(
                    _error!,
                    style: EqTypography.bodyM.copyWith(
                      color: Colors.red.shade700,
                    ),
                  ),
                  const SizedBox(height: EqSpacing.md),
                ],

                // --- Actions --------------------------------------------------
                EqButton(
                  label: 'Save to my profile',
                  onPressed: _saving ? null : _save,
                  isLoading: _saving,
                ),
                const SizedBox(height: EqSpacing.sm),
                TextButton(
                  onPressed: _saving ? null : _skip,
                  child: Text(
                    'Skip — save the licence without updating my profile',
                    style: EqTypography.bodyM.copyWith(
                      color: EqColours.deep.withValues(alpha: 0.6),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: EqSpacing.xl),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: EqSpacing.sm),
      child: Text(
        text,
        style: EqTypography.label.copyWith(
          color: EqColours.ink.withValues(alpha: 0.5),
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
