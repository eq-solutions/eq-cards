import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/analytics/analytics_service.dart';
import '../../../../core/error/user_messages.dart';
import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../../core/validators/input_validators.dart';
import '../../../../core/widgets/eq_app_bar.dart';
import '../../../../core/widgets/eq_button.dart';
import '../../../../core/widgets/eq_text_field.dart';
import '../../data/models/profile.dart';
import '../notifiers/profile_notifier.dart';

class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _mobile = TextEditingController();
  final _email = TextEditingController();
  final _street = TextEditingController();
  final _suburb = TextEditingController();
  final _state = TextEditingController();
  final _postcode = TextEditingController();
  final _emergencyName = TextEditingController();
  final _emergencyRel = TextEditingController();
  final _emergencyMobile = TextEditingController();

  DateTime? _dateOfBirth;
  bool _saving = false;
  bool _hydrated = false;
  String? _error;

  /// The profile as it was when the screen loaded. Used at save time to
  /// compute which fields just got filled (for `profile_field_filled` events)
  /// and whether the profile transitioned from incomplete to complete (for
  /// the `profile_completed` event).
  Profile? _initial;

  @override
  void initState() {
    super.initState();
    // Wait for the provider's future before hydrating. `valueOrNull` in
    // initState would race the async build() of `ProfileNotifier` and silently
    // fail to hydrate on cold-load (deep link, browser refresh, tests).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final profile = await ref.read(profileNotifierProvider.future);
        if (!mounted || _hydrated) return;
        if (profile != null) {
          setState(() {
            _hydrate(profile);
            _hydrated = true;
          });
        } else {
          _hydrated = true;
        }
      } catch (_) {
        // Provider error — leave the form empty so the user can still type.
        _hydrated = true;
      }
    });
  }

  void _hydrate(Profile p) {
    _initial = p;
    _fullName.text = p.fullName ?? '';
    _mobile.text = p.mobile ?? '';
    _email.text = p.email ?? '';
    _street.text = p.addressStreet ?? '';
    _suburb.text = p.addressSuburb ?? '';
    _state.text = p.addressState ?? '';
    _postcode.text = p.addressPostcode ?? '';
    _emergencyName.text = p.emergencyContactName ?? '';
    _emergencyRel.text = p.emergencyContactRelationship ?? '';
    _emergencyMobile.text = p.emergencyContactMobile ?? '';
    _dateOfBirth = p.dateOfBirth;
  }

  @override
  void dispose() {
    _fullName.dispose();
    _mobile.dispose();
    _email.dispose();
    _street.dispose();
    _suburb.dispose();
    _state.dispose();
    _postcode.dispose();
    _emergencyName.dispose();
    _emergencyRel.dispose();
    _emergencyMobile.dispose();
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
    if (!_formKey.currentState!.validate()) return;
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

    final draft = Profile(
      id: userId,
      fullName: _textOrNull(_fullName.text),
      dateOfBirth: _dateOfBirth,
      mobile: _textOrNull(_mobile.text),
      email: _textOrNull(_email.text),
      addressStreet: _textOrNull(_street.text),
      addressSuburb: _textOrNull(_suburb.text),
      addressState: _textOrNull(_state.text),
      addressPostcode: _textOrNull(_postcode.text),
      emergencyContactName: _textOrNull(_emergencyName.text),
      emergencyContactRelationship: _textOrNull(_emergencyRel.text),
      emergencyContactMobile: _textOrNull(_emergencyMobile.text),
    );

    try {
      await ref.read(profileNotifierProvider.notifier).save(draft);
      _emitFieldEvents(_initial, draft);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = userMessageForError(e);
        });
      }
    }
  }

  String? _textOrNull(String value) {
    final t = value.trim();
    return t.isEmpty ? null : t;
  }

  /// Fires `profile_field_filled` for each field that transitioned from
  /// null/empty to a non-empty value. Fires `profile_completed` once if the
  /// profile transitioned from incomplete to complete.
  ///
  /// Per ARCHITECTURE §10 — events are user-action events, fired from the
  /// screen layer where the transition is observable.
  void _emitFieldEvents(Profile? before, Profile after) {
    bool justFilled(String? oldVal, String? newVal) =>
        (oldVal == null || oldVal.isEmpty) &&
        (newVal != null && newVal.isNotEmpty);

    void track(String field, String? oldVal, String? newVal) {
      if (justFilled(oldVal, newVal)) {
        unawaited(
          AnalyticsService.track('profile_field_filled', {'field': field}),
        );
      }
    }

    track('full_name', before?.fullName, after.fullName);
    track('mobile', before?.mobile, after.mobile);
    track('email', before?.email, after.email);
    track('address_street', before?.addressStreet, after.addressStreet);
    track('address_suburb', before?.addressSuburb, after.addressSuburb);
    track('address_state', before?.addressState, after.addressState);
    track('address_postcode', before?.addressPostcode, after.addressPostcode);
    track(
      'emergency_contact_name',
      before?.emergencyContactName,
      after.emergencyContactName,
    );
    track(
      'emergency_contact_relationship',
      before?.emergencyContactRelationship,
      after.emergencyContactRelationship,
    );
    track(
      'emergency_contact_mobile',
      before?.emergencyContactMobile,
      after.emergencyContactMobile,
    );
    if ((before?.dateOfBirth == null) && (after.dateOfBirth != null)) {
      unawaited(
        AnalyticsService.track(
          'profile_field_filled',
          const {'field': 'date_of_birth'},
        ),
      );
    }

    final wasComplete = before?.isComplete ?? false;
    if (!wasComplete && after.isComplete) {
      unawaited(AnalyticsService.track('profile_completed'));
    }
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
      appBar: const EqAppBar(title: 'Edit profile'),
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
              _SectionHeader('You'),
              EqTextField(controller: _fullName, label: 'Full name'),
              const SizedBox(height: EqSpacing.md),
              InkWell(
                onTap: _pickDob,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Date of birth',
                    filled: true,
                    fillColor: EqColours.ice,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  child: Text(dobLabel, style: EqTypography.bodyL),
                ),
              ),
              const SizedBox(height: EqSpacing.md),
              EqTextField(
                controller: _mobile,
                label: 'Mobile',
                keyboardType: TextInputType.phone,
                validator: validateMobile,
              ),
              const SizedBox(height: EqSpacing.md),
              EqTextField(
                controller: _email,
                label: 'Email',
                keyboardType: TextInputType.emailAddress,
                validator: validateEmail,
              ),
              const SizedBox(height: EqSpacing.lg),
              _SectionHeader('Address'),
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
                      validator: validateAuState,
                    ),
                  ),
                  const SizedBox(width: EqSpacing.md),
                  Expanded(
                    child: EqTextField(
                      controller: _postcode,
                      label: 'Postcode',
                      keyboardType: TextInputType.number,
                      validator: validatePostcode,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: EqSpacing.lg),
              _SectionHeader('Emergency contact'),
              EqTextField(controller: _emergencyName, label: 'Name'),
              const SizedBox(height: EqSpacing.md),
              EqTextField(
                controller: _emergencyRel,
                label: 'Relationship',
              ),
              const SizedBox(height: EqSpacing.md),
              EqTextField(
                controller: _emergencyMobile,
                label: 'Mobile',
                keyboardType: TextInputType.phone,
                validator: validateMobile,
              ),
              const SizedBox(height: EqSpacing.xl),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: EqSpacing.md),
                  child: Text(
                    _error!,
                    style: EqTypography.bodyM.copyWith(color: EqColours.error),
                  ),
                ),
              EqButton(
                label: 'Save',
                onPressed: _saving ? null : _save,
                isLoading: _saving,
                fullWidth: true,
              ),
            ],
          ),
          ),
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
      padding: const EdgeInsets.only(bottom: EqSpacing.sm),
      child: Text(text, style: EqTypography.headingM),
    );
  }
}
