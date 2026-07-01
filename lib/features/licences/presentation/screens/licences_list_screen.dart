import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/design/design_version.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/error/user_messages.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/shell/complete_profile_banner.dart';
import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../../core/utils/photo_upload.dart';
import '../../../../core/utils/pick_image.dart';
import '../../../../core/widgets/eq_app_bar.dart';
import '../../../../core/widgets/eq_button.dart';
import '../../../../core/widgets/eq_card.dart';
import '../../../../core/widgets/ocr_loading_dialog.dart';
import '../../../../core/widgets/offline_banner.dart';
import '../../../auth/auth.dart';
import '../../../certificates/data/models/certificate.dart';
import '../../../certificates/presentation/cert_capture_flow.dart'
    show certCaptureFlow;
import '../../../certificates/presentation/notifiers/certificates_list_notifier.dart';
import '../../../connections/presentation/notifiers/connections_notifier.dart';
import '../../../connections/presentation/widgets/pending_connections_banner.dart';
import '../../../consent/consent_gate.dart';
import '../../../profile/presentation/notifiers/profile_notifier.dart';
import '../../../profile/presentation/screens/profile_fill_from_licence_screen.dart'
    show DlProfileFill;
import '../../../settings/data/workspace_repository.dart';
import '../../../workers/data/models/worker.dart';
import '../../data/ocr_service.dart';
import '../helpers/licence_crop.dart';
import '../helpers/licences_list_helpers.dart';
import '../notifiers/licence_types_provider.dart';
import '../notifiers/licences_list_notifier.dart';
import '../widgets/expiry_badge.dart';
import '../widgets/wallet_completion_nudge.dart';
import 'licence_crop_screen.dart';
import 'licence_edit_screen.dart';

const _cardSecondary = Color(0xFFB9C2D6);
const _cardMuted = Color(0xFF7E879C);
const _cardVerifiedBg = Color(0x2E22C55E);
const _cardVerifiedFg = Color(0xFF86EFAC);
const _cardSeparator = Color(0x1AFFFFFF);
const _cardQrBg = Color(0x12FFFFFF);
const _cardQrFg = Color(0xFFCBD5E1);
const _cardChipBg = Color(0x1AFFFFFF);
const _cardChipFg = Color(0xFFE6EBF5);

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

  void _showQrStub() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('QR sign-in coming soon.'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: EqColours.ink,
        duration: Duration(seconds: 2),
      ),
    );
  }

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
    final asyncCerts = ref.watch(certificatesListNotifierProvider);
    final asyncTypes = ref.watch(licenceTypesProvider);
    final designVersion = ref.watch(designVersionNotifierProvider);

    final licences = asyncLicences.value;
    final certs = asyncCerts.value;
    final bool fromCache = ref.watch(licencesFromCacheProvider) ?? false;

    final profile = ref.watch(profileNotifierProvider).value;
    final tenants = ref.watch(myTenantsProvider).value ?? [];
    final activeTenant = tenants.isEmpty
        ? null
        : tenants.firstWhere((t) => t.isActive, orElse: () => tenants.first);
    final user = Supabase.instance.client.auth.currentUser;
    final appMeta = user?.appMetadata ?? const <String, dynamic>{};
    final role = appMeta['eq_role'] as String?;
    final orgName = activeTenant == null
        ? (appMeta['tenant_name'] as String? ?? '—')
        : activeTenant.isPersonal
            ? 'Personal'
            : activeTenant.name;
    final displayName = profile?.fullName;
    final idInitials = _cardInitials(displayName ?? '');
    final roleLabel = role != null ? kEqRoleLabels[role] : null;
    final typeLabel = _cardTypeLabel(role);
    final workerId = _cardWorkerId(user?.id ?? '');
    final issued = _cardIssuedDate(user?.createdAt);

    // Combined wallet: licences are the primary source. A hard error there
    // shows the error state; certificates failing degrades silently to
    // "licences only" rather than blanking the whole wallet.
    final bothLoading = licences == null &&
        certs == null &&
        (asyncLicences.isLoading || asyncCerts.isLoading);
    final licencesFailed = asyncLicences.hasError && licences == null;

    return ConsentGate(
      child: Scaffold(
        appBar: EqAppBar(
          title: 'Wallet',
          withBranding: true,
        actions: [
          if (!kIsWeb) ...[
            IconButton(
              icon: const Icon(Icons.camera_alt_outlined),
              tooltip: 'Scan a licence',
              onPressed: () => unawaited(_captureFlow(context, ref)),
            ),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'More options',
              onPressed: () => _showAddSheet(context, ref),
            ),
          ] else
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add to wallet',
              onPressed: () => _showAddSheet(context, ref),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Offline banner — amber strip shown when serving from cache with
          // no network. Collapses to zero height when online or no cache.
          OfflineBanner(fromCache: fromCache),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                unawaited(
                  ref.read(licencesListNotifierProvider.notifier).refresh(),
                );
                await ref
                    .read(certificatesListNotifierProvider.notifier)
                    .refresh();
              },
              child: Builder(
                builder: (context) {
                  if (bothLoading) return const _LicencesSkeleton();
                  if (licencesFailed) {
                    return ListView(
                      children: [
                        const CompleteProfileBanner(),
                        Padding(
                          padding: const EdgeInsets.all(EqSpacing.lg),
                          child: _ListErrorState(
                            error: asyncLicences.error!,
                            onRetry: () => ref
                                .read(licencesListNotifierProvider.notifier)
                                .refresh(),
                            onSignInAgain: () =>
                                ref.read(authRepositoryProvider).signOut(),
                          ),
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

                  final items = _buildWalletItems(
                    licences ?? const [],
                    certs ?? const [],
                    typeMap,
                  );

                  final licencesList = licences ?? const <Licence>[];
                  final certsList = certs ?? const <Certificate>[];
                  final validCount = licencesList
                      .where((l) => !l.isExpired && !l.isExpiringWithin(days: 30))
                      .length
                    + certsList
                      .where((c) => !c.isExpired && !c.isExpiringWithin(days: 30))
                      .length;
                  final expiringCount = licencesList
                      .where((l) => l.isExpiringWithin(days: 30))
                      .length
                    + certsList.where((c) => c.isExpiringWithin(days: 30)).length;
                  final expiredCount = licencesList.where((l) => l.isExpired).length
                    + certsList.where((c) => c.isExpired).length;
                  // Urgent items from the unified list — includes both licences
                  // and certificates so CPR and other certs appear here.
                  final urgentItems = items
                      .where((item) => item.isExpired || item.isExpiringSoon)
                      .toList();

                  // Show the once-ever tap-to-copy hint on the next frame if
                  // the wallet has anything in it. Post-frame so we don't
                  // trigger UI changes during build.
                  if (items.isNotEmpty && !_hintCheckedThisSession) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) unawaited(_maybeShowTapToCopyHint(context));
                    });
                  }

                  final idCard = _WalletIdCard(
                    initials: idInitials,
                    displayName: displayName,
                    roleLabel: roleLabel,
                    typeLabel: typeLabel,
                    orgName: orgName,
                    workerId: workerId,
                    issued: issued,
                    onQrTap: _showQrStub,
                  );

                  if (items.isEmpty) {
                    return ListView(
                      padding: const EdgeInsets.all(EqSpacing.md),
                      children: [
                        idCard,
                        const SizedBox(height: EqSpacing.md),
                        const CompleteProfileBanner(),
                        const PendingConnectionsBanner(),
                        const _ConnectNudgeBanner(),
                        _EmptyState(
                          onScan: () => unawaited(_captureFlow(context, ref)),
                          onManual: () => context.go(Routes.licenceCreate),
                          version: designVersion,
                        ),
                      ],
                    );
                  }

                  // Search matches title / number / issuer / type; filter
                  // narrows by expiry-bucket. Both apply across licences and
                  // certificates.
                  final filtered = _applyWalletFilters(items);
                  return ListView(
                    padding: const EdgeInsets.all(EqSpacing.md),
                    children: [
                      idCard,
                      const SizedBox(height: EqSpacing.md),
                      if (items.isNotEmpty) ...[
                        _WalletHealthCard(
                          validCount: validCount,
                          expiringCount: expiringCount,
                          expiredCount: expiredCount,
                        ),
                        const SizedBox(height: EqSpacing.md),
                      ],
                      if (urgentItems.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.only(
                              left: EqSpacing.xs, bottom: EqSpacing.sm),
                          child: Text('Needs attention',
                              style: EqTypography.label),
                        ),
                        ...urgentItems.take(4).map((item) => Padding(
                              padding: const EdgeInsets.only(
                                  bottom: EqSpacing.sm),
                              child: _WalletTile(item: item),
                            )),
                        const SizedBox(height: EqSpacing.sm),
                      ],
                      const CompleteProfileBanner(),
                      const PendingConnectionsBanner(),
                      const _ConnectNudgeBanner(),
                      if (items.length < 6)
                        WalletCompletionNudge(
                          existingTypeCodes: licencesList
                              .map((l) => l.licenceType)
                              .toSet(),
                        ),
                      _SearchAndFilterBar(
                        query: _query,
                        controller: _searchCtrl,
                        filter: _filter,
                        onQueryChanged: (q) => setState(() => _query = q),
                        onFilterChanged: (f) => setState(() => _filter = f),
                        totalCount: items.length,
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
                            style: EqTypography.bodyM
                                .copyWith(color: EqColours.grey),
                            textAlign: TextAlign.center,
                          ),
                        )
                      else
                        for (final item in filtered) ...[
                          _WalletTile(item: item),
                          const SizedBox(height: EqSpacing.sm),
                        ],
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  /// Builds the unified wallet list — licences + certificates mapped to a
  /// common tile shape — sorted by expiry urgency (soonest first, no-expiry
  /// last). Pure given its inputs.
  List<_WalletItem> _buildWalletItems(
    List<Licence> licences,
    List<Certificate> certs,
    Map<String, String> typeMap,
  ) {
    final items = <_WalletItem>[
      for (final l in licences)
        _WalletItem(
          icon: Icons.badge_outlined,
          title: typeMap[l.licenceType] ?? l.licenceType,
          meta: l.licenceNumber,
          expiry: l.neverExpires ? null : l.expiryDate,
          neverExpires: l.neverExpires,
          onTap: () => context.go(Routes.licenceDetailFor(l.id!)),
          searchText:
              '${typeMap[l.licenceType] ?? l.licenceType} ${l.licenceNumber}'
                  .toLowerCase(),
          photoUrl: l.photoFrontSignedUrl,
          credentialId: l.id,
          isPrivate: l.isPrivate,
          onTogglePrivate: () => ref
              .read(licencesListNotifierProvider.notifier)
              .togglePrivacy(l),
        ),
      for (final c in certs)
        _WalletItem(
          icon: c.isPdf
              ? Icons.picture_as_pdf_outlined
              : Icons.workspace_premium_outlined,
          title: c.title,
          meta: c.issuer ??
              (certTypeLabels[c.certificateType] ?? c.certificateType),
          expiry: c.expiryDate,
          onTap: () => context.go(Routes.certificateDetailFor(c.id!)),
          searchText: '${c.title} ${c.issuer ?? ''} '
                  '${certTypeLabels[c.certificateType] ?? c.certificateType}'
              .toLowerCase(),
        ),
    ];
    items.sort((a, b) {
      final ax = a.expiry;
      final bx = b.expiry;
      if (ax == null && bx == null) return a.title.compareTo(b.title);
      if (ax == null) return 1;
      if (bx == null) return -1;
      return ax.compareTo(bx);
    });
    return items;
  }

  /// Apply the active search query + expiry filter to the combined list.
  List<_WalletItem> _applyWalletFilters(List<_WalletItem> input) {
    final q = _query.trim().toLowerCase();
    return input.where((item) {
      switch (_filter) {
        case LicenceFilter.all:
          break;
        case LicenceFilter.expiringSoon:
          if (!item.isExpiringSoon) return false;
        case LicenceFilter.expired:
          if (!item.isExpired) return false;
      }
      if (q.isEmpty) return true;
      return item.searchText.contains(q);
    }).toList();
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
              Text('Add to wallet', style: EqTypography.headingM),
              const SizedBox(height: EqSpacing.md),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: Text(
                  kIsWeb ? 'Upload a licence photo' : 'Scan a licence',
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
                title: const Text('Enter a licence manually'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  context.go(Routes.licenceCreate);
                },
              ),
              ListTile(
                leading: const Icon(Icons.workspace_premium_outlined),
                title: Text(
                  kIsWeb ? 'Upload a certificate photo' : 'Scan a certificate',
                ),
                subtitle: const Text(
                  'First aid, working at heights, white card — OCR reads the expiry',
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await certCaptureFlow(context, ref);
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Enter a certificate manually'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  context.go(Routes.certificateCreate);
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
    final picked = await pickImageWithSourceChoice(
      context,
      picker,
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
      builder: (_) => const OcrLoadingDialog(noun: 'licence'),
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

    // Rear-of-card detection: if OCR returned essentially nothing useful —
    // no card number, no expiry, no holder name — the user probably
    // photographed the back. The rear of an Aussie DL is ~80% PDF417
    // barcode; other cards often have barcodes or plain blank backs.
    // Claude Vision can't decode barcodes as structured text. Prompt the
    // user to flip and retry rather than dropping them into a blank form.
    // Note: we do NOT require licenceTypeCandidate == 'driver_licence' here
    // because the type is often null or unknown when scanning the rear.
    final looksLikeRear = !cancelled &&
        extraction != null &&
        extraction!.numberCandidate == null &&
        extraction!.expiryDateCandidate == null &&
        extraction!.holderName == null &&
        extraction!.licenceTypeCandidate == null;
    if (looksLikeRear) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'That looks like the back of the licence — '
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

/// A single entry in the unified wallet — either a licence or a certificate,
/// normalised to a common shape so they render in one list.
class _WalletItem {
  _WalletItem({
    required this.icon,
    required this.title,
    required this.meta,
    required this.expiry,
    required this.onTap,
    required this.searchText,
    this.photoUrl,
    this.neverExpires = false,
    this.credentialId,
    this.isPrivate,
    this.onTogglePrivate,
  });

  final IconData icon;
  final String title;
  final String meta;
  final DateTime? expiry;
  final VoidCallback onTap;
  final String searchText;
  /// Signed URL for the front-of-licence photo. Shown as a thumbnail when
  /// present; falls back to the icon chip when null.
  final String? photoUrl;
  /// When true this credential never expires — isExpired and isExpiringSoon
  /// always return false, and the tile shows a "No expiry" chip instead of a
  /// date.
  final bool neverExpires;
  /// UUID of the `worker_credentials` row. When non-null and the user is on
  /// iOS, an "Add to Apple Wallet" button is shown on the tile.
  final String? credentialId;
  /// Whether this licence is marked private. Null = no privacy toggle for
  /// this item type (e.g. certificates that don't support the flag yet).
  final bool? isPrivate;
  /// Called when the user taps the privacy lock icon. Null = no toggle shown.
  final Future<void> Function()? onTogglePrivate;

  bool get isExpired =>
      !neverExpires && expiry != null && DateTime.now().isAfter(expiry!);

  bool get isExpiringSoon {
    if (neverExpires) return false;
    final e = expiry;
    if (e == null || isExpired) return false;
    return e.difference(DateTime.now()).inDays <= 30;
  }
}

/// V9 wallet tile — photo thumbnail (or icon chip) + title + meta + expiry badge.
/// On iOS web, shows an "Add to Apple Wallet" button for items with a
/// `credentialId`.
class _WalletTile extends StatefulWidget {
  const _WalletTile({required this.item});

  final _WalletItem item;

  @override
  State<_WalletTile> createState() => _WalletTileState();
}

class _WalletTileState extends State<_WalletTile> {
  bool _toggling = false;
  bool? _optimisticPrivate;

  Future<void> _handlePrivacyToggle() async {
    if (_toggling || widget.item.onTogglePrivate == null) return;

    final currentlyPrivate = widget.item.isPrivate ?? false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(currentlyPrivate ? 'Make visible to employers?' : 'Hide this licence?'),
        content: Text(
          currentlyPrivate
              ? 'Employers will be able to see it in compliance views and expiry reports.'
              : "It won't appear in employer views or expiry reports. Only you can see it.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(currentlyPrivate ? 'Make visible' : 'Hide it'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _toggling = true;
      _optimisticPrivate = !currentlyPrivate;
    });
    try {
      await widget.item.onTogglePrivate!();
    } catch (_) {
      // Revert optimistic flip on error.
    } finally {
      if (mounted) setState(() { _toggling = false; _optimisticPrivate = null; });
    }
  }

  Widget _iconChip(IconData icon) => ColoredBox(
        color: EqColours.ice,
        child: Center(child: Icon(icon, size: 18, color: EqColours.deep)),
      );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: [widget.item.title, if (widget.item.meta.isNotEmpty) widget.item.meta].join(', '),
      excludeSemantics: true,
      child: EqCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        onTap: widget.item.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                // Thumbnail: show licence photo if available, otherwise icon chip.
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: widget.item.photoUrl != null
                        ? Image.network(
                            widget.item.photoUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                _iconChip(widget.item.icon),
                          )
                        : _iconChip(widget.item.icon),
                  ),
                ),
                const SizedBox(width: EqSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.item.title,
                        style: EqTypography.bodyL
                            .copyWith(fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.item.meta.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          widget.item.meta,
                          style: EqTypography.label
                              .copyWith(color: EqColours.g500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: EqSpacing.sm),
                if (widget.item.neverExpires)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: EqSpacing.sm,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: EqColours.ice,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '∞  No expiry',
                      style: EqTypography.label.copyWith(
                        color: EqColours.deep,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else if (widget.item.expiry != null)
                  ExpiryBadge(expiry: widget.item.expiry!)
                else
                  Text(
                    'No expiry',
                    style:
                        EqTypography.label.copyWith(color: EqColours.grey),
                  ),
                if (widget.item.onTogglePrivate != null) ...[
                  const SizedBox(width: EqSpacing.sm),
                  GestureDetector(
                    onTap: _handlePrivacyToggle,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: _toggling
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: EqColours.g500,
                              ),
                            )
                          : Icon(
                              (_optimisticPrivate ?? widget.item.isPrivate ?? false)
                                  ? Icons.lock_rounded
                                  : Icons.lock_open_rounded,
                              size: 18,
                              color: (_optimisticPrivate ?? widget.item.isPrivate ?? false)
                                  ? EqColours.ink
                                  : EqColours.g500,
                            ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.onScan,
    required this.onManual,
    this.version = DesignVersion.linear,
  });

  final VoidCallback onScan;
  final VoidCallback onManual;
  final DesignVersion version;

  @override
  Widget build(BuildContext context) {
    return switch (version) {
      DesignVersion.linear => _IllustrationEmpty(onScan: onScan, onManual: onManual),
      DesignVersion.wallet => _ActionGridEmpty(onScan: onScan, onManual: onManual),
      DesignVersion.photoFirst => _DashboardEmpty(onScan: onScan, onManual: onManual),
    };
  }
}

// Linear — scan-first. Primary CTA goes straight to the capture flow;
// manual entry is a secondary text link so it's there without competing.
class _IllustrationEmpty extends StatelessWidget {
  const _IllustrationEmpty({required this.onScan, required this.onManual});

  final VoidCallback onScan;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: EqSpacing.lg,
        vertical: EqSpacing.xxl,
      ),
      child: Column(
        children: [
          Image.asset(
            'assets/icon/launcher.png',
            width: 96,
            height: 96,
            errorBuilder: (_, _, _) => const Icon(
              Icons.badge_outlined,
              size: 64,
              color: EqColours.grey,
            ),
          ),
          const SizedBox(height: EqSpacing.md),
          Text(
            'Your licences, one place',
            style: EqTypography.headingL,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: EqSpacing.sm),
          Text(
            kIsWeb
                ? 'Upload a photo of your licence — we read the number, type, and expiry automatically.'
                : 'Take a photo of your licence — we read the number, type, and expiry automatically.',
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
          EqButton(
            label: kIsWeb ? 'Upload a licence photo' : 'Scan my licence',
            onPressed: onScan,
            fullWidth: true,
          ),
          const SizedBox(height: EqSpacing.sm),
          TextButton(
            onPressed: onManual,
            child: Text(
              'Enter manually instead',
              style: EqTypography.bodyM.copyWith(color: EqColours.grey),
            ),
          ),
          const WalletEmptySuggestions(),
        ],
      ),
    );
  }
}

// Wallet → 2-action grid: scan (OCR) / manual entry.
class _ActionGridEmpty extends StatelessWidget {
  const _ActionGridEmpty({required this.onScan, required this.onManual});

  final VoidCallback onScan;
  final VoidCallback onManual;

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
            kIsWeb
                ? 'Upload a photo and we read the fields. Or type them in.'
                : 'Take a photo and we read the fields. Or type them in.',
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
            icon: kIsWeb ? Icons.upload_outlined : Icons.camera_alt_outlined,
            label: kIsWeb ? 'Upload a licence photo' : 'Scan my licence',
            subtitle: kIsWeb
                ? 'Pick a photo; we read the number, type, and expiry.'
                : 'Take a photo; we read the number, type, and expiry.',
            onTap: onScan,
          ),
          const SizedBox(height: EqSpacing.sm),
          _ActionTile(
            icon: Icons.edit_outlined,
            label: 'Enter manually',
            subtitle: 'Type in the details yourself.',
            onTap: onManual,
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
        color: EqColours.surface,
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
  const _DashboardEmpty({required this.onScan, required this.onManual});

  final VoidCallback onScan;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(EqSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: EqSpacing.md),
          const Row(
            children: [
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
              color: EqColours.white,
              border: Border.all(color: EqColours.outlineSoft),
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
                  label: kIsWeb ? 'Upload a licence photo' : 'Scan my licence',
                  onPressed: onScan,
                  fullWidth: true,
                ),
                const SizedBox(height: EqSpacing.sm),
                TextButton(
                  onPressed: onManual,
                  child: Text(
                    'Enter manually instead',
                    style: EqTypography.bodyM.copyWith(color: EqColours.grey),
                  ),
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

/// Nudge banner shown on the wallet when a worker has licences but no employer
/// connection. Disappears automatically once they connect to any org.
class _ConnectNudgeBanner extends ConsumerWidget {
  const _ConnectNudgeBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenants = ref.watch(myTenantsProvider).value;
    if (tenants == null) return const SizedBox.shrink();
    if (!tenants.every((t) => t.isPersonal)) return const SizedBox.shrink();
    // If the employer has already sent an invite, that banner handles it.
    final pending = ref.watch(pendingConnectionsNotifierProvider).value;
    if (pending != null && pending.isNotEmpty) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => context.push(Routes.connect),
      child: Container(
        margin: const EdgeInsets.only(bottom: EqSpacing.md),
        padding: const EdgeInsets.all(EqSpacing.md),
        decoration: BoxDecoration(
          color: EqColours.white,
          borderRadius: BorderRadius.circular(12),
          border: Border(
            left: const BorderSide(color: EqColours.deep, width: 4),
            top: BorderSide(color: EqColours.outlineSoft),
            right: BorderSide(color: EqColours.outlineSoft),
            bottom: BorderSide(color: EqColours.outlineSoft),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.business_center_outlined,
              color: EqColours.deep,
              size: 20,
            ),
            const SizedBox(width: EqSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Connect to your employer',
                    style: EqTypography.bodyL.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Share your credentials with your company',
                    style: EqTypography.label.copyWith(
                      color: EqColours.g500,
                    ),
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
    );
    unawaited(_controller.repeat(reverse: true));
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
        final t = (_controller.value - 0.5).abs() * 2; // 0..1..0
        final fill = Color.lerp(
          EqColours.surface,
          EqColours.outlineSoft,
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
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: EqColours.outlineSoft),
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
            fillColor: EqColours.surface,
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
                backgroundColor: EqColours.surface,
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

// ── ID-card helper functions ──────────────────────────────────────────────────

String _cardInitials(String name) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return 'EQ';
  if (parts.length == 1) return parts[0][0].toUpperCase();
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}

String? _cardTypeLabel(String? role) => switch (role) {
      'employee' => 'Direct employee',
      'labour_hire' => 'Labour hire',
      'manager' => 'Manager',
      'supervisor' => 'Supervisor',
      'apprentice' => 'Apprentice',
      _ => null,
    };

String _cardWorkerId(String uuid) {
  final hex = uuid.replaceAll('-', '');
  if (hex.length < 4) return 'EQ-0000';
  final tail = hex.substring(hex.length - 4);
  final n = int.parse(tail, radix: 16) % 9000 + 1000;
  return 'EQ-$n';
}

String _cardIssuedDate(String? createdAt) {
  if (createdAt == null || createdAt.isEmpty) return '—';
  try {
    return DateFormat('MMM yyyy').format(DateTime.parse(createdAt));
  } catch (_) {
    return '—';
  }
}

// ── Wallet ID card ────────────────────────────────────────────────────────────

class _WalletIdCard extends StatelessWidget {
  const _WalletIdCard({
    required this.initials,
    required this.displayName,
    required this.roleLabel,
    required this.typeLabel,
    required this.orgName,
    required this.workerId,
    required this.issued,
    required this.onQrTap,
  });

  final String initials;
  final String? displayName;
  final String? roleLabel;
  final String? typeLabel;
  final String orgName;
  final String workerId;
  final String issued;
  final VoidCallback onQrTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: EqColours.ink,
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(EqSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                'EQ',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'WORKER CARD',
                style: TextStyle(
                  color: _cardMuted,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _cardVerifiedBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_outlined,
                        size: 10, color: _cardVerifiedFg),
                    SizedBox(width: 4),
                    Text(
                      'Verified',
                      style: TextStyle(
                        color: _cardVerifiedFg,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: EqSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: EqColours.sky,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: EqSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName ?? '—',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (roleLabel != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        roleLabel!,
                        style: const TextStyle(
                          color: _cardSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (typeLabel != null) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _cardChipBg,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 5,
                              height: 5,
                              decoration: const BoxDecoration(
                                color: EqColours.sky,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              typeLabel!,
                              style: const TextStyle(
                                color: _cardChipFg,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: EqSpacing.md),
          Container(
            padding: const EdgeInsets.only(top: EqSpacing.md),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: _cardSeparator)),
            ),
            child: Row(
              children: [
                Expanded(child: _IdGridCell(label: 'Company', value: orgName)),
                Expanded(
                    child: _IdGridCell(label: 'Worker ID', value: workerId)),
                Expanded(child: _IdGridCell(label: 'Issued', value: issued)),
              ],
            ),
          ),
          const SizedBox(height: EqSpacing.sm),
          GestureDetector(
            onTap: onQrTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: _cardQrBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.qr_code, size: 13, color: _cardQrFg),
                  SizedBox(width: 6),
                  Text(
                    'Tap to show QR for site sign-in',
                    style: TextStyle(
                      color: _cardQrFg,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IdGridCell extends StatelessWidget {
  const _IdGridCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _cardMuted,
            fontSize: 8,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

// ── Licence health card ───────────────────────────────────────────────────────

class _WalletHealthCard extends StatelessWidget {
  const _WalletHealthCard({
    required this.validCount,
    required this.expiringCount,
    required this.expiredCount,
  });

  final int validCount;
  final int expiringCount;
  final int expiredCount;

  @override
  Widget build(BuildContext context) {
    return EqCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: EqSpacing.md, vertical: 10),
            child: Row(
              children: [
                Text(
                  'Licence health',
                  style: EqTypography.label
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _HealthCell(
                    count: validCount,
                    label: 'Valid',
                    color: EqColours.success,
                  ),
                ),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(
                  child: _HealthCell(
                    count: expiringCount,
                    label: 'Expiring',
                    color: EqColours.warning,
                  ),
                ),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(
                  child: _HealthCell(
                    count: expiredCount,
                    label: 'Expired',
                    color: EqColours.error,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HealthCell extends StatelessWidget {
  const _HealthCell({
    required this.count,
    required this.label,
    required this.color,
  });

  final int count;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: EqSpacing.md),
      child: Column(
        children: [
          Text(
            '$count',
            style: EqTypography.headingL.copyWith(
              fontWeight: FontWeight.w800,
              color: count > 0 ? color : EqColours.ink,
            ),
          ),
          const SizedBox(height: EqSpacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: count > 0 ? color : EqColours.grey,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(label, style: EqTypography.label),
            ],
          ),
        ],
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
