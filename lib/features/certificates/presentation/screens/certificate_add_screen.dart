import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../../core/widgets/eq_app_bar.dart';
import '../../../../core/widgets/eq_button.dart';
import '../../../../core/widgets/eq_text_field.dart';
import '../../data/certificate_repository.dart';
import '../../data/models/certificate.dart';
import '../notifiers/certificates_list_notifier.dart';

/// OCR result + photo bytes passed from the scan-certificate flow.
class CertPrefill {
  const CertPrefill({this.photoBytes, this.expiryDate, this.suggestedType});
  final Uint8List? photoBytes;
  final DateTime? expiryDate;
  final String? suggestedType;
}

class CertificateAddScreen extends ConsumerStatefulWidget {
  const CertificateAddScreen({super.key, this.certificateId, this.prefill});

  /// Non-null when editing an existing certificate.
  final String? certificateId;

  /// Pre-populated data from the scan flow — null when adding manually.
  final CertPrefill? prefill;

  @override
  ConsumerState<CertificateAddScreen> createState() =>
      _CertificateAddScreenState();
}

class _CertificateAddScreenState extends ConsumerState<CertificateAddScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _issuer = TextEditingController();
  final _notes = TextEditingController();

  String _certType = 'first_aid';
  DateTime? _issueDate;
  DateTime? _expiryDate;

  // Pending file — set when the user picks a file.
  Uint8List? _pendingBytes;
  String? _pendingFileName;
  String? _pendingMime;

  // Existing cert when editing.
  Certificate? _existing;

  bool _saving = false;
  bool _loading = false;
  String? _error;

  bool get _isEdit => widget.certificateId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _hydrate());
    } else {
      _applyPrefill();
    }
  }

  void _applyPrefill() {
    final pre = widget.prefill;
    if (pre == null) return;
    if (pre.photoBytes != null) {
      _pendingBytes = pre.photoBytes;
      _pendingMime = 'image/jpeg';
      _pendingFileName = 'scanned_cert.jpg';
    }
    if (pre.expiryDate != null) _expiryDate = pre.expiryDate;
    if (pre.suggestedType != null &&
        certTypeLabels.containsKey(pre.suggestedType)) {
      _certType = pre.suggestedType!;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _issuer.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _hydrate() async {
    setState(() => _loading = true);
    try {
      final certs = await ref
          .read(certificateRepositoryProvider)
          .getAllForCurrentUser();
      final match =
          certs.where((c) => c.id == widget.certificateId).toList();
      if (match.isEmpty || !mounted) return;
      final cert = match.first;
      _existing = cert;
      _title.text = cert.title;
      _issuer.text = cert.issuer ?? '';
      _notes.text = cert.notes ?? '';
      _certType = cert.certificateType;
      _issueDate = cert.issueDate;
      _expiryDate = cert.expiryDate;
    } catch (_) {
      // Non-fatal — user can re-enter.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return; // user cancelled
      final file = result.files.first;
      if (file.bytes == null) {
        // Some browsers return a file entry without bytes even with
        // withData:true — show an actionable error rather than silently
        // dropping the selection.
        setState(
          () => _error =
              'Could not read the file. Try a different format or browser.',
        );
        return;
      }

      final ext = (file.extension ?? 'pdf').toLowerCase();
      final mime = ext == 'pdf' ? 'application/pdf' : 'image/$ext';

      setState(() {
        _pendingBytes = file.bytes;
        _pendingFileName = file.name;
        _pendingMime = mime;
        _error = null;
      });
    } catch (e) {
      setState(
        () => _error =
            'Could not open file picker. Try refreshing the page.',
      );
    }
  }

  Future<void> _pickDate({required bool isExpiry}) async {
    final initial = isExpiry ? _expiryDate : _issueDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2040),
    );
    if (picked == null) return;
    setState(() {
      if (isExpiry) {
        _expiryDate = picked;
      } else {
        _issueDate = picked;
      }
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_isEdit && _pendingBytes == null) {
      setState(() => _error = 'Please pick a file first.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final repo = ref.read(certificateRepositoryProvider);
      final uid = Supabase.instance.client.auth.currentUser!.id;
      // Client-side UUID for the storage path. On insert the DB row uses this
      // as a predictable path prefix; on edit we use the existing row's id.
      final certId = _existing?.id ?? const Uuid().v4();

      // Initialised here so dart2js never sees these as uninitialised across
      // the await boundary — a late-init sentinel read is the root cause of
      // LateInitializationError: Field '' has not been initialized (#EQ-CARDS-B).
      var filePath = '';
      var fileType = '';

      if (_pendingBytes != null && _pendingMime != null) {
        final mime = _pendingMime!;
        final ext = mime == 'application/pdf'
            ? 'pdf'
            : mime.split('/').last.replaceAll('jpeg', 'jpg');
        fileType = mime == 'application/pdf' ? 'pdf' : 'image';
        filePath = await repo.uploadFile(
          certificateId: certId,
          ext: ext,
          bytes: _pendingBytes!,
          mimeType: mime,
        );
      } else {
        // Edit with no new file — keep existing.
        if (_existing == null) {
          setState(() {
            _saving = false;
            _error = 'Certificate data not loaded. Please go back and try again.';
          });
          return;
        }
        filePath = _existing!.filePath;
        fileType = _existing!.fileType;
      }

      final cert = Certificate(
        id: _isEdit ? certId : null,
        userId: uid,
        title: _title.text.trim(),
        certificateType: _certType,
        issuer: _issuer.text.trim().isEmpty ? null : _issuer.text.trim(),
        issueDate: _issueDate,
        expiryDate: _expiryDate,
        filePath: filePath,
        fileType: fileType,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      );

      if (_isEdit) {
        await repo.update(cert.copyWith(id: certId));
      } else {
        await repo.insert(cert);
      }

      if (!mounted) return;
      unawaited(
        ref.read(certificatesListNotifierProvider.notifier).refresh(),
      );
      context.pop();
    } catch (e) {
      setState(() {
        _saving = false;
        _error = 'Could not save certificate. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: EqAppBar(title: _isEdit ? 'Edit certificate' : 'Add certificate'),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final dateFmt = DateFormat('d MMM yyyy');

    return Scaffold(
      appBar: EqAppBar(
        title: _isEdit ? 'Edit certificate' : 'Add certificate',
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(EqSpacing.lg),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── File picker ─────────────────────────────────
              _FilePicker(
                fileName: _pendingFileName ??
                    _existing?.filePath.split('/').last,
                onPick: _pickFile,
                required: !_isEdit,
              ),
              const SizedBox(height: EqSpacing.lg),

              // ── OCR prefill banner ───────────────────────────
              if (widget.prefill != null) ...[
                Container(
                  padding: const EdgeInsets.all(EqSpacing.md),
                  decoration: BoxDecoration(
                    color: EqColours.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: EqColours.sky, width: 1),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.auto_awesome_outlined,
                        size: 20,
                        color: EqColours.deep,
                      ),
                      const SizedBox(width: EqSpacing.sm),
                      Expanded(
                        child: Text(
                          'Photo scanned. Check type and expiry — OCR can misread small text.',
                          style: EqTypography.bodyM,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: EqSpacing.lg),
              ],

              // ── Title ────────────────────────────────────────
              EqTextField(
                label: 'Title',
                hint: 'e.g. First Aid Certificate',
                controller: _title,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: EqSpacing.md),

              // ── Type ─────────────────────────────────────────
              _TypeDropdown(
                value: _certType,
                onChanged: (v) => setState(() => _certType = v),
              ),
              const SizedBox(height: EqSpacing.md),

              // ── Issuer ───────────────────────────────────────
              EqTextField(
                label: 'Issuer (optional)',
                hint: 'e.g. St John, SafeWork NSW',
                controller: _issuer,
              ),
              const SizedBox(height: EqSpacing.md),

              // ── Dates ────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: _DateTile(
                      label: 'Issue date',
                      value: _issueDate != null
                          ? dateFmt.format(_issueDate!)
                          : null,
                      onTap: () => _pickDate(isExpiry: false),
                    ),
                  ),
                  const SizedBox(width: EqSpacing.md),
                  Expanded(
                    child: _DateTile(
                      label: 'Expiry date',
                      value: _expiryDate != null
                          ? dateFmt.format(_expiryDate!)
                          : null,
                      onTap: () => _pickDate(isExpiry: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: EqSpacing.md),

              // ── Notes ────────────────────────────────────────
              TextFormField(
                controller: _notes,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Notes (optional)',
                  filled: true,
                  fillColor: EqColours.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: EqSpacing.xl),

              if (_error != null) ...[
                Text(
                  _error!,
                  style: EqTypography.label.copyWith(color: EqColours.error),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: EqSpacing.md),
              ],

              EqButton(
                label: _saving ? 'Saving…' : 'Save',
                onPressed: _saving ? null : _save,
                fullWidth: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _FilePicker extends StatelessWidget {
  const _FilePicker({
    required this.fileName,
    required this.onPick,
    required this.required,
  });

  final String? fileName;
  final VoidCallback onPick;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPick,
      child: Container(
        padding: const EdgeInsets.all(EqSpacing.md),
        decoration: BoxDecoration(
          color: EqColours.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: EqColours.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              fileName != null
                  ? (fileName!.toLowerCase().endsWith('.pdf')
                      ? Icons.picture_as_pdf_outlined
                      : Icons.image_outlined)
                  : Icons.upload_file_outlined,
              color: EqColours.deep,
            ),
            const SizedBox(width: EqSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName ?? 'Pick a file',
                    style: EqTypography.bodyM.copyWith(
                      color:
                          fileName != null ? EqColours.ink : EqColours.grey,
                      fontWeight: fileName != null
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'PDF, JPG, or PNG${required ? ' — required' : ''}',
                    style:
                        EqTypography.label.copyWith(color: EqColours.grey),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: EqColours.grey),
          ],
        ),
      ),
    );
  }
}

class _TypeDropdown extends StatelessWidget {
  const _TypeDropdown({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Type', style: EqTypography.label),
        const SizedBox(height: EqSpacing.xs),
        // Plain DropdownButton — _certType is tracked in CertificateAddScreen
        // state so there is no need for FormField machinery here, and using
        // DropdownButtonFormField introduced a late-init hazard via the
        // FormField/RestorationMixin _errorText field (#EQ-CARDS-B).
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
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              isDense: true,
              underline: const SizedBox.shrink(),
              style: EqTypography.bodyM.copyWith(color: EqColours.ink),
              dropdownColor: EqColours.white,
              items: certTypeLabels.entries
                  .map(
                    (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                  )
                  .toList(),
              onChanged: (v) => onChanged(v ?? value),
            ),
          ),
        ),
      ],
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(EqSpacing.md),
        decoration: BoxDecoration(
          color: EqColours.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: EqColours.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: EqTypography.label),
            const SizedBox(height: EqSpacing.xs),
            Text(
              value ?? 'Not set',
              style: EqTypography.bodyM.copyWith(
                color: value != null ? EqColours.ink : EqColours.grey,
                fontWeight:
                    value != null ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
