import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/analytics/analytics_service.dart';
import '../../../../core/error/user_messages.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../../core/utils/photo_upload.dart';
import '../../../../core/validators/input_validators.dart';
import '../../../../core/widgets/eq_app_bar.dart';
import '../../../../core/widgets/eq_button.dart';
import '../../../../core/widgets/eq_text_field.dart';
import '../../data/licence_repository.dart';
import '../../data/models/licence.dart';
import '../../data/models/licence_type.dart';
import '../../data/ocr_service.dart';
import '../notifiers/licence_types_provider.dart';
import '../notifiers/licences_list_notifier.dart';

class LicencePrefill {
  const LicencePrefill({this.photoBytes, this.ocr});
  final Uint8List? photoBytes;
  final OcrExtraction? ocr;
}

class LicenceEditScreen extends ConsumerStatefulWidget {
  const LicenceEditScreen({super.key, this.licenceId, this.prefill});

  final String? licenceId;
  final LicencePrefill? prefill;

  @override
  ConsumerState<LicenceEditScreen> createState() => _LicenceEditScreenState();
}

class _LicenceEditScreenState extends ConsumerState<LicenceEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _number = TextEditingController();
  final _state = TextEditingController();
  final _authority = TextEditingController();
  final _notes = TextEditingController();
  final _metadataControllers = <String, TextEditingController>{};

  String? _typeCode;
  DateTime? _issueDate;
  DateTime? _expiryDate;
  Uint8List? _pendingFront;
  Uint8List? _pendingBack;
  Licence? _existing;

  bool _saving = false;
  bool _loading = true;
  String? _error;

  bool get _isEdit => widget.licenceId != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _hydrate());
  }

  @override
  void dispose() {
    _number.dispose();
    _state.dispose();
    _authority.dispose();
    _notes.dispose();
    for (final c in _metadataControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _hydrate() async {
    if (_isEdit) {
      try {
        final existing = await ref
            .read(licenceRepositoryProvider)
            .getById(widget.licenceId!);
        if (!mounted) return;
        setState(() {
          _existing = existing;
          _typeCode = existing.licenceType;
          _number.text = existing.licenceNumber;
          _issueDate = existing.issueDate;
          _expiryDate = existing.expiryDate;
          _state.text = existing.state ?? '';
          _authority.text = existing.issuingAuthority ?? '';
          _notes.text = existing.notes ?? '';
          for (final entry in existing.metadata.entries) {
            _metadataControllers[entry.key] =
                TextEditingController(text: '${entry.value}');
          }
          _loading = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _error = userMessageForError(e);
          _loading = false;
        });
      }
    } else {
      // New licence — apply OCR prefill if any.
      final pre = widget.prefill;
      final ocr = pre?.ocr;
      if (ocr?.numberCandidate != null) {
        _number.text = ocr!.numberCandidate!;
      }
      if (ocr?.licenceTypeCandidate != null) {
        _typeCode = ocr!.licenceTypeCandidate;
      }
      if (ocr?.stateCandidate != null) {
        _state.text = ocr!.stateCandidate!;
      }
      if (ocr?.issuingAuthorityCandidate != null) {
        _authority.text = ocr!.issuingAuthorityCandidate!;
      } else if (ocr?.licenceTypeCandidate == 'driver_licence' &&
          ocr?.stateCandidate != null) {
        // Fallback: for driver licences, infer the issuing authority from the
        // state if Claude didn't read one off the card.
        final inferred = _driverLicenceAuthorityForState(ocr!.stateCandidate!);
        if (inferred != null) _authority.text = inferred;
      }
      _issueDate = ocr?.issueDateCandidate;
      _expiryDate = ocr?.expiryDateCandidate;
      _pendingFront = pre?.photoBytes;
      setState(() => _loading = false);
    }
  }

  /// Authority for an Australian driver licence by state. Used as a defensive
  /// fallback when OCR returned a state but no authority text. Authoritative
  /// names come from the issuing agencies' current branding.
  static String? _driverLicenceAuthorityForState(String state) {
    return switch (state) {
      'NSW' => 'Service NSW',
      'VIC' => 'VicRoads',
      'QLD' => 'Queensland Transport',
      'WA' => 'Department of Transport WA',
      'SA' => 'Service SA',
      'TAS' => 'Department of State Growth',
      'NT' => 'Motor Vehicle Registry NT',
      'ACT' => 'Access Canberra',
      _ => null,
    };
  }

  List<_MetaField> _metaFieldsFor(String? code) {
    return switch (code) {
      'medicare' => const [_MetaField(key: 'irn', label: 'IRN')],
      'driver_licence' => const [_MetaField(key: 'class', label: 'Class')],
      'forklift_hrwl' => const [
          _MetaField(key: 'class', label: 'Class (LF/LO/LR)'),
          _MetaField(key: 'ticket_number', label: 'Ticket number'),
        ],
      _ => const [],
    };
  }

  Future<void> _pickDate({required bool forExpiry}) async {
    final now = DateTime.now();
    final initial = (forExpiry ? _expiryDate : _issueDate) ?? now;
    final first = forExpiry ? now : DateTime(now.year - 30);
    final last = forExpiry ? DateTime(now.year + 30) : now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (picked != null) {
      setState(() {
        if (forExpiry) {
          _expiryDate = picked;
        } else {
          _issueDate = picked;
        }
      });
    }
  }

  Future<void> _pickPhoto({required bool front}) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      if (front) {
        _pendingFront = bytes;
      } else {
        _pendingBack = bytes;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_typeCode == null || _issueDate == null || _expiryDate == null) {
      setState(() => _error = 'Type, issue date and expiry date are required.');
      return;
    }

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

    try {
      final repo = ref.read(licenceRepositoryProvider);
      final uploader = ref.read(photoUploadProvider);

      // Step 1: upsert the row first (no photo paths if it's new).
      final draft = Licence(
        id: _existing?.id,
        userId: userId,
        licenceType: _typeCode!,
        licenceNumber: _number.text.trim(),
        issueDate: _issueDate!,
        expiryDate: _expiryDate!,
        state: _textOrNull(_state.text),
        issuingAuthority: _textOrNull(_authority.text),
        notes: _textOrNull(_notes.text),
        photoFrontPath: _existing?.photoFrontPath,
        photoBackPath: _existing?.photoBackPath,
        metadata: <String, dynamic>{
          for (final entry in _metadataControllers.entries)
            if (entry.value.text.trim().isNotEmpty)
              entry.key: entry.value.text.trim(),
        },
      );
      final isInsert = _existing == null;
      var saved = await repo.upsert(draft);
      if (isInsert) {
        unawaited(
          AnalyticsService.track('licence_added', {
            'licence_type': saved.licenceType,
            'via_ocr': widget.prefill?.ocr != null,
          }),
        );
      }

      // Step 2: upload photos if user picked new ones.
      String? frontPath = saved.photoFrontPath;
      String? backPath = saved.photoBackPath;
      if (_pendingFront != null) {
        frontPath = await uploader.uploadLicencePhotoBytes(
          licenceId: saved.id!,
          slot: 'front',
          bytes: _pendingFront!,
        );
      }
      if (_pendingBack != null) {
        backPath = await uploader.uploadLicencePhotoBytes(
          licenceId: saved.id!,
          slot: 'back',
          bytes: _pendingBack!,
        );
      }

      // Step 3: update the licence row with photo paths if anything changed.
      if (frontPath != saved.photoFrontPath ||
          backPath != saved.photoBackPath) {
        saved = await repo.upsert(
          saved.copyWith(
            photoFrontPath: frontPath,
            photoBackPath: backPath,
          ),
        );
      }

      ref.invalidate(licencesListNotifierProvider);
      if (mounted) context.go(Routes.licencesList);
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final asyncTypes = ref.watch(licenceTypesProvider);

    return Scaffold(
      appBar: EqAppBar(
        title: _isEdit ? 'Edit licence' : 'New licence',
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(EqSpacing.md),
            children: [
              asyncTypes.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Could not load types: $e'),
                data: (types) => _TypeDropdown(
                  types: types,
                  value: _typeCode,
                  onChanged: (v) => setState(() => _typeCode = v),
                ),
              ),
              const SizedBox(height: EqSpacing.md),
              EqTextField(
                controller: _number,
                label: 'Licence number',
                validator: validateLicenceNumber,
              ),
              const SizedBox(height: EqSpacing.md),
              _DateField(
                label: 'Issue date',
                value: _issueDate,
                onTap: () => _pickDate(forExpiry: false),
              ),
              const SizedBox(height: EqSpacing.md),
              _DateField(
                label: 'Expiry date',
                value: _expiryDate,
                onTap: () => _pickDate(forExpiry: true),
              ),
              const SizedBox(height: EqSpacing.md),
              EqTextField(
                controller: _state,
                label: 'State (NSW, VIC, etc.)',
                validator: validateAuState,
              ),
              const SizedBox(height: EqSpacing.md),
              EqTextField(
                controller: _authority,
                label: 'Issuing authority',
              ),
              ..._metaFieldsFor(_typeCode).expand(
                (f) => [
                  const SizedBox(height: EqSpacing.md),
                  EqTextField(
                    controller: _metadataControllers.putIfAbsent(
                      f.key,
                      () => TextEditingController(),
                    ),
                    label: f.label,
                  ),
                ],
              ),
              const SizedBox(height: EqSpacing.md),
              EqTextField(controller: _notes, label: 'Notes'),
              const SizedBox(height: EqSpacing.lg),
              _PhotoSlot(
                label: 'Front photo',
                bytes: _pendingFront,
                existingUrl: _existing?.photoFrontSignedUrl,
                onTap: () => _pickPhoto(front: true),
              ),
              const SizedBox(height: EqSpacing.md),
              _PhotoSlot(
                label: 'Back photo (optional)',
                bytes: _pendingBack,
                existingUrl: _existing?.photoBackSignedUrl,
                onTap: () => _pickPhoto(front: false),
              ),
              const SizedBox(height: EqSpacing.xl),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: EqSpacing.md),
                  child: Text(
                    _error!,
                    style:
                        EqTypography.bodyM.copyWith(color: EqColours.error),
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
    );
  }
}

class _MetaField {
  const _MetaField({required this.key, required this.label});
  final String key;
  final String label;
}

class _TypeDropdown extends StatelessWidget {
  const _TypeDropdown({
    required this.types,
    required this.value,
    required this.onChanged,
  });

  final List<LicenceType> types;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: 'Licence type',
        filled: true,
        fillColor: EqColours.ice,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide.none,
        ),
      ),
      items: types
          .map((t) => DropdownMenuItem(value: t.code, child: Text(t.label)))
          .toList(),
      onChanged: onChanged,
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = value == null
        ? 'Tap to choose'
        : DateFormat('d MMM yyyy').format(value!);
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: EqColours.ice,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide.none,
          ),
        ),
        child: Text(text, style: EqTypography.bodyL),
      ),
    );
  }
}

class _PhotoSlot extends StatelessWidget {
  const _PhotoSlot({
    required this.label,
    required this.bytes,
    required this.existingUrl,
    required this.onTap,
  });

  final String label;
  final Uint8List? bytes;
  final String? existingUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: EqColours.ice,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (bytes != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(bytes!, fit: BoxFit.cover),
              )
            else if (existingUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(existingUrl!, fit: BoxFit.cover),
              )
            else
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.camera_alt_outlined,
                      color: EqColours.grey,
                    ),
                    const SizedBox(height: EqSpacing.sm),
                    Text(label, style: EqTypography.label),
                  ],
                ),
              ),
            if (bytes != null || existingUrl != null)
              Positioned(
                top: EqSpacing.sm,
                right: EqSpacing.sm,
                child: Container(
                  padding: const EdgeInsets.all(EqSpacing.xs),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.refresh,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
