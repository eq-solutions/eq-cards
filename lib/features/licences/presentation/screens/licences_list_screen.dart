import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/design/design_version.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/error/user_messages.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/shell/complete_profile_banner.dart';
import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../../core/utils/photo_upload.dart';
import '../../../../core/widgets/eq_app_bar.dart';
import '../../../../core/widgets/eq_button.dart';
import '../../../auth/auth.dart';
import '../../../profile/presentation/screens/profile_fill_from_licence_screen.dart'
    show DlProfileFill;
import 'licence_crop_screen.dart';
import '../../data/models/licence.dart';
import '../../data/ocr_service.dart';
import '../helpers/licence_crop.dart';
import '../helpers/licences_list_helpers.dart';
import '../notifiers/licence_types_provider.dart';
import '../notifiers/licences_list_notifier.dart';
import '../widgets/licence_card.dart';
import 'licence_edit_screen.dart';

class LicencesListScreen extends ConsumerStatefulWidget {
  const LicencesListScreen({super.key});

  @override
  ConsumerState<LicencesListScreen> createState() =>
      _LicencesListScreenState();
}

class _LicencesListScreenState extends ConsumerState<LicencesListScreen> {
  static const _hintShownKey = 'eq_cards.hint.tap_to_copy_shown';

  String _query = '';
  LicenceFilter _filter = LicenceFilter.all;
  final _searchCtrl = TextEditingController();
  bool _hintCheckedThisSession = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Once-ever onboarding hint: shown the first time the user lands on the
  /// licence list with at least one licence. Persisted in shared_preferences
  /// so it never appears again. Skipped silently on errors so a prefs failure
  /// never blocks the list rendering.
  Future<void> _maybeShowTapToCopyHint(BuildContext context) async {
    if (_hintCheckedThisSession) return;
    _hintCheckedThisSession = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_hintShownKey) ?? false) return;
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            "Tip: tap any field on a licence to copy it. That's the wedge.",
          ),
          duration: const Duration(seconds: 8),
          behavior: SnackBarBehavior.floating,
          backgroundColor: EqColours.deep,
          action: SnackBarAction(
            label: 'Got it',
            textColor: EqColours.white,
            onPressed: () {},
          ),
        ),
      );
      await prefs.setBool(_hintShownKey, true);
    } catch (_) {
      // shared_preferences unreachable on web in some private-mode browsers;
      // silently skip rather than crash the list render.
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncLicences = ref.watch(licencesListNotifierProvider);
    final asyncTypes = ref.watch(licenceTypesProvider);
    final designVersion = ref.watch(designVersionNotifierProvider);

    return Scaffold(
      appBar: EqAppBar(
        title: 'Licences',
        withBranding: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add licence',
            onPressed: () => _showAddSheet(context, ref),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async =>
            ref.read(licencesListNotifierProvider.notifier).refresh(),
        child: asyncLicences.when(
          loading: () => const _LicencesSkeleton(),
          error: (e, _) => ListView(
            children: [
              const CompleteProfileBanner(),
              Padding(
                padding: const EdgeInsets.all(EqSpacing.lg),
                child: _ListErrorState(
                  error: e,
                  onRetry: () => ref
                      .read(licencesListNotifierProvider.notifier)
                      .refresh(),
                  onSignInAgain: () => ref
                      .read(authRepositoryProvider)
                      .signOut(),
                ),
              ),
            ],
          ),
          data: (licences) {
            // Show the once-ever tap-to-copy hint on the next frame if we
            // have at least one licence. Wrapped in a post-frame callback
            // so we don't trigger UI changes during build.
            if (licences.isNotEmpty && !_hintCheckedThisSession) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) unawaited(_maybeShowTapToCopyHint(context));
              });
            }
            if (licences.isEmpty) {
              return ListView(
                children: [
                  const CompleteProfileBanner(),
                  _EmptyState(
                    onAdd: () => _showAddSheet(context, ref),
                    version: designVersion,
                  ),
                ],
              );
            }
            final typeMap = <String, String>{};
            asyncTypes.whenData((types) {
              for (final t in types) {
                typeMap[t.code] = t.label;
              }
            });
            // Filter + search the licence list. Search matches type label
            // and licence number (case-insensitive). Filter narrows by
            // expiry-bucket. Both apply, search first then filter.
            final filtered = _applyFilters(licences, typeMap);
            return ListView(
              padding: const EdgeInsets.all(EqSpacing.md),
              children: [
                const CompleteProfileBanner(),
                _SearchAndFilterBar(
                  query: _query,
                  controller: _searchCtrl,
                  filter: _filter,
                  onQueryChanged: (q) => setState(() => _query = q),
                  onFilterChanged: (f) => setState(() => _filter = f),
                  totalCount: licences.length,
                  shownCount: filtered.length,
                ),
                const SizedBox(height: EqSpacing.sm),
                if (filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: EqSpacing.xl,
                      horizontal: EqSpacing.lg,
                    ),
                    child: Text(
                      'No matches for these filters.',
                      style: EqTypography.bodyM.copyWith(color: EqColours.grey),
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  for (final licence in filtered) ...[
                    LicenceCard(
                      licence: licence,
                      typeLabel: typeMap[licence.licenceType] ??
                          licence.licenceType,
                      onTap: () =>
                          context.go(Routes.licenceDetailFor(licence.id!)),
                      onLongPress: () =>
                          _showQuickActions(context, ref, licence),
                      version: designVersion,
                    ),
                    const SizedBox(height: EqSpacing.sm),
                  ],
              ],
            );
          },
        ),
      ),
    );
  }

  /// Apply search + filter — delegates to the pure helper. Kept as a
  /// thin instance method so the call site reads cleanly.
  List<Licence> _applyFilters(
    List<Licence> input,
    Map<String, String> typeMap,
  ) =>
      applyLicenceFilters(
        input,
        typeLabels: typeMap,
        filter: _filter,
        query: _query,
      );

  /// Long-press quick-actions sheet on a licence card. Shortcuts the
  /// detail-screen → menu → action chain to one tap.
  Future<void> _showQuickActions(
    BuildContext context,
    WidgetRef ref,
    Licence licence,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: EqColours.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.open_in_new_outlined),
              title: const Text('Open'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.go(Routes.licenceDetailFor(licence.id!));
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.go(Routes.licenceEditFor(licence.id!));
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddSheet(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: EqColours.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(EqSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Add a licence', style: EqTypography.headingM),
              const SizedBox(height: EqSpacing.md),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: Text(
                  kIsWeb ? 'Upload a photo' : 'Capture with camera',
                ),
                subtitle: const Text(
                  'OCR pre-fills number, type, and dates from the photo',
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _captureFlow(context, ref);
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Enter manually'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  context.go(Routes.licenceCreate);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _captureFlow(BuildContext context, WidgetRef ref) async {
    final picker = ImagePicker();
    // Always open the camera directly — on mobile web this maps to
    // <input capture="environment"> which captures JPEG; on desktop web
    // it falls back to file picker. The old ImageSource.gallery path on
    // mobile web let users pick HEIC library photos which broke OCR.
    final picked = await picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
      imageQuality: 85,
    );
    if (picked == null || !context.mounted) return;

    // Cropping step — native Flutter UI on web (no JS bridge); ImageCropper
    // on native builds. The web native crop decodes the picked image, shows
    // draggable corner handles, and re-encodes the selection as JPEG before
    // returning. This eliminates background noise for better OCR accuracy.
    // croppedFile is only set on native — used by extractFromFile (ML Kit).
    // On web the native crop returns Uint8List directly.
    XFile? croppedFile;
    Uint8List rawBytes;
    if (kIsWeb) {
      final pickedBytes = await picked.readAsBytes();
      if (!context.mounted) return;
      final cropped = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => LicenceCropScreen(imageBytes: pickedBytes),
        ),
      );
      if (cropped == null || !context.mounted) return; // user cancelled
      rawBytes = cropped;
    } else {
      final c = await cropLicencePhoto(
        context,
        picked,
        actionLabel: 'Scan licence',
      );
      if (c == null || !context.mounted) return;
      croppedFile = c;
      rawBytes = await c.readAsBytes();
    }
    // The native crop re-encodes to JPEG, so on web the mime is always
    // image/jpeg. On native, the original mime from the picker is used
    // (ImageCropper also outputs JPEG, so this is also always image/jpeg).
    final pickedMime = kIsWeb ? 'image/jpeg' : picked.mimeType;

    if (!context.mounted) return;
    // Show a loading dialog while OCR runs. The Edge Function round-trip
    // can take 3-8s; without this the user thinks nothing is happening and
    // may pick the photo again. After 8s the dialog exposes a "Skip OCR"
    // button which pops the dialog with `true` — we race that against the
    // OCR future so a cancel actually short-circuits the flow instead of
    // silently waiting for OCR to finish in the background.
    final loadingDialog = showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _OcrLoadingDialog(),
    );

    unawaited(
      Sentry.addBreadcrumb(
        Breadcrumb(
          category: 'ocr',
          message: 'capture_flow_started',
          data: {
            'platform': kIsWeb ? 'web' : 'mobile',
            'mime_picked': pickedMime ?? 'unknown',
            'raw_bytes': rawBytes.length,
          },
          level: SentryLevel.info,
        ),
      ),
    );

    // Convert + EXIF-strip on web before anything leaves the device. iPhone
    // photos are often HEIC, which Anthropic Vision rejects. The browser
    // can natively decode HEIC; flutter_image_compress's web path uses a
    // canvas which produces a JPEG output. If that fails we fall through
    // to raw bytes and the Edge Function returns a clearer error.
    var bytes = rawBytes;
    // Default to JPEG after a successful compression; only fall back to
    // the actual picked mime when compression fails. Sending HEIC bytes
    // labelled as JPEG (the old behaviour) was the silent-iPhone-OCR-fail
    // pathway — Anthropic rejected the lie with an opaque error.
    var mime = 'image/jpeg';
    if (kIsWeb) {
      try {
        bytes = await stripExifAndCompress(rawBytes);
        unawaited(
          Sentry.addBreadcrumb(
            Breadcrumb(
              category: 'ocr',
              message: 'compress_succeeded',
              data: {'output_bytes': bytes.length},
            ),
          ),
        );
      } catch (e, st) {
        unawaited(
          Sentry.addBreadcrumb(
            Breadcrumb(
              category: 'ocr',
              message: 'compress_failed',
              data: {'error': e.toString()},
              level: SentryLevel.warning,
            ),
          ),
        );
        unawaited(Sentry.captureException(e, stackTrace: st));
        bytes = rawBytes;
        // Do NOT override mime with pickedMime here. The crop step
        // (ImageCropper, compressFormat: jpg) already converted the
        // image to JPEG, so rawBytes are always JPEG regardless of the
        // original format (e.g. HEIC from an iPhone library photo).
        // Overriding mime with 'image/heic' (the original picker mime)
        // was the silent iOS OCR-fail pathway — the Edge Function
        // rejected HEIC with `unsupported_mime_type`.
        // Only honour pickedMime if it's a format the Edge Function accepts.
        final supportedMime = RegExp(
          r'^image/(jpeg|jpg|png|webp|gif)$',
          caseSensitive: false,
        );
        if (pickedMime != null && supportedMime.hasMatch(pickedMime)) {
          mime = pickedMime;
        }
        // Otherwise keep mime = 'image/jpeg' — the crop already produced JPEG.
      }
    }

    OcrExtraction? extraction;
    String? userVisibleError;
    var cancelled = false;

    // Race the OCR call against the user tapping "Skip OCR". Whichever
    // resolves first drives the flow; the loser's future still settles
    // harmlessly in the background.
    final ocr = ref.read(ocrServiceProvider);
    final ocrCall = (kIsWeb || croppedFile == null
            ? ocr.extractFromBytesViaEdgeFunction(bytes, mimeType: mime)
            : ocr.extractFromFile(File(croppedFile.path)))
        .then<void>((r) {
      extraction = r;
      unawaited(
        Sentry.addBreadcrumb(
          Breadcrumb(
            category: 'ocr',
            message: 'extract_succeeded',
            data: {
              'has_number': r.numberCandidate != null,
              'has_type': r.licenceTypeCandidate != null,
              'has_state': r.stateCandidate != null,
              'has_expiry': r.expiryDateCandidate != null,
            },
          ),
        ),
      );
    }).catchError((Object e, StackTrace st) {
      unawaited(Sentry.captureException(e, stackTrace: st));
      userVisibleError = ocrErrorMessage(e);
    });

    final cancelCall = loadingDialog.then<void>((result) {
      // result is `true` only when the user tapped "Skip OCR". A `null`
      // (system back) or `false` is treated as not-a-deliberate-cancel.
      if (result ?? false) cancelled = true;
    });

    await Future.any<void>([ocrCall, cancelCall]);

    if (cancelled) {
      unawaited(
        Sentry.addBreadcrumb(
          Breadcrumb(
            category: 'ocr',
            message: 'user_skipped',
            level: SentryLevel.info,
          ),
        ),
      );
    } else {
      // OCR finished first — dismiss the dialog before navigating. Wrapped
      // in try so a near-simultaneous tap on Skip doesn't double-pop.
      try {
        if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      } catch (_) {
        // Already dismissed — fine.
      }
    }
    // Let the dialog and OCR futures settle in the background regardless
    // of who won the race. Without this, an OCR future that resolves
    // *after* the user cancelled would surface as an unhandled async
    // error in debug builds.
    unawaited(loadingDialog);
    unawaited(ocrCall);

    if (!context.mounted) return;
    if (cancelled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'OCR skipped — fill in the licence manually.',
          ),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          backgroundColor: EqColours.ink,
        ),
      );
    } else if (userVisibleError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "OCR didn't run: $userVisibleError. You can still fill the "
            'licence in manually.',
          ),
          duration: const Duration(seconds: 6),
          behavior: SnackBarBehavior.floating,
          backgroundColor: EqColours.ink,
        ),
      );
    }
    final licencePrefill = LicencePrefill(
      photoBytes: bytes,
      // On cancel, drop the OCR result even if it raced in just before
      // the user tapped Skip — they explicitly asked to fill manually.
      ocr: cancelled ? null : extraction,
    );

    // Rear-of-card detection: if OCR thinks it's a driver licence but found
    // no holder name, no card number, and no expiry, the user probably
    // photographed the back. The rear of an Aussie DL is ~80% PDF417
    // barcode — Claude Vision can't decode it as structured text. Prompt
    // the user to flip the card and try again rather than silently
    // dropping them into an empty licence form.
    final looksLikeRear = !cancelled &&
        extraction != null &&
        extraction!.licenceTypeCandidate == 'driver_licence' &&
        extraction!.numberCandidate == null &&
        extraction!.holderName == null &&
        extraction!.expiryDateCandidate == null;
    if (looksLikeRear) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            "That looks like the back of the licence — "
            'flip to the front and scan again.',
          ),
          duration: const Duration(seconds: 6),
          behavior: SnackBarBehavior.floating,
          backgroundColor: EqColours.ink,
        ),
      );
      return; // Stay on the list; user can tap + to try again.
    }

    // Driver licence + profile fields extracted → ask the user to confirm
    // their details before continuing to save the licence itself.
    // Assign to a local variable so the null check promotes the type.
    final e = extraction;
    if (!cancelled &&
        e != null &&
        e.licenceTypeCandidate == 'driver_licence' &&
        e.hasProfileFields) {
      context.go(
        Routes.profileFillFromLicence,
        extra: DlProfileFill(
          holderName: e.holderName,
          dateOfBirth: e.dateOfBirth,
          addressStreet: e.addressStreet,
          addressSuburb: e.addressSuburb,
          addressState: e.addressState,
          addressPostcode: e.addressPostcode,
          licencePrefill: licencePrefill,
        ),
      );
    } else {
      context.go(Routes.licenceCreate, extra: licencePrefill);
    }
  }

}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd, this.version = DesignVersion.linear});

  final VoidCallback onAdd;
  final DesignVersion version;

  @override
  Widget build(BuildContext context) {
    return switch (version) {
      DesignVersion.linear => _IllustrationEmpty(onAdd: onAdd),
      DesignVersion.wallet => _ActionGridEmpty(onAdd: onAdd),
      DesignVersion.photoFirst => _DashboardEmpty(onAdd: onAdd),
    };
  }
}

// Linear → simple icon + headline + button.
class _IllustrationEmpty extends StatelessWidget {
  const _IllustrationEmpty({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: EqSpacing.lg,
        vertical: EqSpacing.xxl,
      ),
      child: Column(
        children: [
          // EQ launcher mark — first impression for a new user opening the
          // wallet for the first time.
          Image.asset(
            'assets/icon/launcher.png',
            width: 96,
            height: 96,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.badge_outlined,
              size: 64,
              color: EqColours.grey,
            ),
          ),
          const SizedBox(height: EqSpacing.md),
          Text(
            'No licences yet',
            style: EqTypography.headingL,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: EqSpacing.sm),
          Text(
            'Add your first licence — White Card, Driver Licence, First Aid, '
            'whatever you carry on site.',
            style: EqTypography.bodyM.copyWith(color: EqColours.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: EqSpacing.xs),
          Text(
            'Then tap any field to copy it straight onto an induction form.',
            style: EqTypography.bodyM.copyWith(
              color: EqColours.deep,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: EqSpacing.xl),
          EqButton(label: 'Add licence', onPressed: onAdd, fullWidth: true),
        ],
      ),
    );
  }
}

// Wallet → 3-action grid: Take photo / Upload / Manual entry.
class _ActionGridEmpty extends StatelessWidget {
  const _ActionGridEmpty({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(EqSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: EqSpacing.lg),
          Text(
            'Build your wallet',
            style: EqTypography.headingL,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: EqSpacing.sm),
          Text(
            'Three ways to add a licence. Pick whatever fits.',
            style: EqTypography.bodyM.copyWith(color: EqColours.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: EqSpacing.xs),
          Text(
            'Once added, tap any field to copy it onto an induction form.',
            style: EqTypography.bodyM.copyWith(
              color: EqColours.deep,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: EqSpacing.xl),
          _ActionTile(
            icon: Icons.camera_alt_outlined,
            label: 'Photo + auto-fill',
            subtitle: 'Snap your licence; we read the fields.',
            onTap: onAdd,
          ),
          const SizedBox(height: EqSpacing.sm),
          _ActionTile(
            icon: Icons.upload_outlined,
            label: 'Upload from gallery',
            subtitle: 'Pick an existing photo from your phone.',
            onTap: onAdd,
          ),
          const SizedBox(height: EqSpacing.sm),
          _ActionTile(
            icon: Icons.edit_outlined,
            label: 'Type it in',
            subtitle: 'Manual entry. Faster if you know the details.',
            onTap: onAdd,
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label. $subtitle',
      button: true,
      excludeSemantics: true,
      child: Material(
        color: EqColours.ice,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(EqSpacing.md),
            child: Row(
              children: [
                Icon(icon, color: EqColours.deep),
                const SizedBox(width: EqSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: EqTypography.bodyL.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: EqSpacing.xs),
                      Text(subtitle, style: EqTypography.label),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: EqColours.grey),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Photo-first → dashboard-style with "0 licences · 0 expiring" stat strip.
class _DashboardEmpty extends StatelessWidget {
  const _DashboardEmpty({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(EqSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: EqSpacing.md),
          Row(
            children: const [
              Expanded(child: _StatTile(value: '0', label: 'Licences')),
              SizedBox(width: EqSpacing.md),
              Expanded(child: _StatTile(value: '0', label: 'Expiring 30d')),
              SizedBox(width: EqSpacing.md),
              Expanded(child: _StatTile(value: '—', label: 'Last copied')),
            ],
          ),
          const SizedBox(height: EqSpacing.xl),
          Container(
            padding: const EdgeInsets.all(EqSpacing.lg),
            decoration: BoxDecoration(
              color: EqColours.ice,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.add_card_outlined,
                  size: 56,
                  color: EqColours.deep,
                ),
                const SizedBox(height: EqSpacing.md),
                Text(
                  "Let's add your first licence",
                  style: EqTypography.headingM,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: EqSpacing.sm),
                Text(
                  'Once you have one, you can tap any field to copy '
                  'it straight onto an induction form.',
                  style: EqTypography.bodyM.copyWith(color: EqColours.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: EqSpacing.lg),
                EqButton(
                  label: 'Add a licence',
                  onPressed: onAdd,
                  fullWidth: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(EqSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: EqColours.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: EqTypography.headingL.copyWith(
              fontWeight: FontWeight.w700,
              color: EqColours.deep,
            ),
          ),
          const SizedBox(height: EqSpacing.xs),
          Text(label, style: EqTypography.label),
        ],
      ),
    );
  }
}

/// 3-card shimmer placeholder shown while licences load. Lays out the same
/// shape as a real list (banner + 3 cards) so the page doesn't reflow when
/// data arrives. Uses a subtle 1.2s pulse driven by `AnimatedOpacity`.
class _LicencesSkeleton extends StatefulWidget {
  const _LicencesSkeleton();

  @override
  State<_LicencesSkeleton> createState() => _LicencesSkeletonState();
}

class _LicencesSkeletonState extends State<_LicencesSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // Pulse between 0.55 and 1.0 opacity on the ice fill colour.
        final t = (_controller.value - 0.5).abs() * 2; // 0..1..0
        final fill = Color.lerp(
          EqColours.ice,
          EqColours.border,
          t,
        )!;
        return ListView(
          padding: const EdgeInsets.all(EqSpacing.md),
          children: [
            _SkeletonBox(width: double.infinity, height: 56, color: fill),
            const SizedBox(height: EqSpacing.sm),
            for (int i = 0; i < 3; i++) ...[
              _SkeletonCard(color: fill),
              const SizedBox(height: EqSpacing.sm),
            ],
          ],
        );
      },
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(EqSpacing.md),
      decoration: BoxDecoration(
        color: EqColours.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: EqColours.border),
      ),
      child: Row(
        children: [
          _SkeletonBox(width: 56, height: 56, color: color),
          const SizedBox(width: EqSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkeletonBox(width: 140, height: 16, color: color),
                const SizedBox(height: EqSpacing.sm),
                _SkeletonBox(width: 100, height: 12, color: color),
                const SizedBox(height: EqSpacing.xs),
                _SkeletonBox(width: 180, height: 12, color: color),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({
    required this.width,
    required this.height,
    required this.color,
  });

  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

/// Search input + filter chips above the licence list. Pure presentational —
/// state lives in [_LicencesListScreenState]. Hidden when the list is so
/// short that filtering would be friction (≤2 licences).
class _SearchAndFilterBar extends StatelessWidget {
  const _SearchAndFilterBar({
    required this.query,
    required this.controller,
    required this.filter,
    required this.onQueryChanged,
    required this.onFilterChanged,
    required this.totalCount,
    required this.shownCount,
  });

  final String query;
  final TextEditingController controller;
  final LicenceFilter filter;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<LicenceFilter> onFilterChanged;
  final int totalCount;
  final int shownCount;

  @override
  Widget build(BuildContext context) {
    if (totalCount <= 2) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          onChanged: onQueryChanged,
          decoration: InputDecoration(
            hintText: 'Search licences',
            prefixIcon: const Icon(Icons.search, color: EqColours.grey),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear, color: EqColours.grey),
                    onPressed: () {
                      controller.clear();
                      onQueryChanged('');
                    },
                  ),
            filled: true,
            fillColor: EqColours.ice,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: EqSpacing.md,
              vertical: EqSpacing.sm,
            ),
          ),
        ),
        const SizedBox(height: EqSpacing.sm),
        Row(
          children: [
            for (final f in LicenceFilter.values) ...[
              ChoiceChip(
                label: Text(f.label),
                selected: filter == f,
                onSelected: (_) => onFilterChanged(f),
                // Deep for contrast against white text (sky failed WCAG).
                selectedColor: EqColours.deep,
                backgroundColor: EqColours.ice,
                labelStyle: TextStyle(
                  color: filter == f ? EqColours.white : EqColours.ink,
                  fontWeight:
                      filter == f ? FontWeight.w600 : FontWeight.w400,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide.none,
                ),
              ),
              const SizedBox(width: EqSpacing.xs),
            ],
            const Spacer(),
            if (query.isNotEmpty || filter != LicenceFilter.all)
              Text(
                '$shownCount of $totalCount',
                style: EqTypography.label.copyWith(color: EqColours.grey),
              ),
          ],
        ),
      ],
    );
  }
}

/// Modal shown while the OCR Edge Function processes an uploaded photo.
/// Initially non-dismissable to prevent the user picking the same photo
/// twice while the round-trip is in flight (3-8s typical on Sonnet vision).
/// After 8 seconds a Cancel button appears so a user can escape if the
/// network has stalled. Anything longer than 8s is past the median p95.
class _OcrLoadingDialog extends StatefulWidget {
  const _OcrLoadingDialog();

  @override
  State<_OcrLoadingDialog> createState() => _OcrLoadingDialogState();
}

class _OcrLoadingDialogState extends State<_OcrLoadingDialog> {
  bool _allowCancel = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _allowCancel = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowCancel,
      child: Dialog(
        backgroundColor: EqColours.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(EqSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: EqColours.sky,
                ),
              ),
              const SizedBox(height: EqSpacing.md),
              Text('Reading your licence…', style: EqTypography.bodyL),
              const SizedBox(height: EqSpacing.xs),
              Text(
                _allowCancel
                    ? 'Still working — slow network? Tap below to enter the '
                        'details yourself instead.'
                    : 'First scan of the day may take a few seconds while we '
                        'warm up the magic-scanner.',
                textAlign: TextAlign.center,
                style: EqTypography.label.copyWith(color: EqColours.grey),
              ),
              if (_allowCancel) ...[
                const SizedBox(height: EqSpacing.md),
                TextButton(
                  // Pop with `true` so the _captureFlow race-handler knows
                  // this was a user-initiated skip, not the dialog being
                  // dismissed because OCR finished.
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(
                    'Skip OCR, fill manually',
                    style: EqTypography.bodyM.copyWith(color: EqColours.deep),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Error state for the licences list — shows a friendly message plus an
/// action that fits the cause. For a NotAuthenticatedFailure (in-session
/// 401, expired refresh token, etc.) the right path is sign-out — which
/// triggers the router redirect to the email-entry screen. For everything
/// else, retry is the right CTA.
class _ListErrorState extends StatelessWidget {
  const _ListErrorState({
    required this.error,
    required this.onRetry,
    required this.onSignInAgain,
  });

  final Object error;
  final Future<void> Function() onRetry;
  final Future<void> Function() onSignInAgain;

  bool get _isAuthError {
    if (error is NotAuthenticatedFailure) return true;
    if (error is ServerFailure) {
      final msg = (error as ServerFailure).message.toLowerCase();
      return msg.contains('jwt') ||
          msg.contains('tenant') ||
          msg.contains('token');
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          _isAuthError ? Icons.lock_outline : Icons.cloud_off_outlined,
          size: 48,
          color: EqColours.grey,
        ),
        const SizedBox(height: EqSpacing.md),
        Text(
          _isAuthError ? 'Sign in again' : "We couldn't load your licences",
          style: EqTypography.headingL,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: EqSpacing.sm),
        Text(
          userMessageForError(error),
          style: EqTypography.bodyM.copyWith(color: EqColours.grey),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: EqSpacing.xl),
        EqButton(
          label: _isAuthError ? 'Sign in again' : 'Try again',
          onPressed: _isAuthError ? onSignInAgain : onRetry,
          fullWidth: true,
        ),
      ],
    );
  }
}
