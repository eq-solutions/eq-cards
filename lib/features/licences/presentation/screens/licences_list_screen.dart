import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/design/design_version.dart';
import '../../../../core/error/user_messages.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/shell/complete_profile_banner.dart';
import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../../core/utils/photo_upload.dart';
import '../../../../core/widgets/eq_app_bar.dart';
import '../../../../core/widgets/eq_button.dart';
import '../../data/ocr_service.dart';
import '../notifiers/licence_types_provider.dart';
import '../notifiers/licences_list_notifier.dart';
import '../widgets/licence_card.dart';
import 'licence_edit_screen.dart';

class LicencesListScreen extends ConsumerWidget {
  const LicencesListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncLicences = ref.watch(licencesListNotifierProvider);
    final asyncTypes = ref.watch(licenceTypesProvider);
    final designVersion = ref.watch(designVersionNotifierProvider);

    return Scaffold(
      appBar: EqAppBar(
        title: 'Licences',
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
                child: Text(
                  'Could not load licences.\n${userMessageForError(e)}',
                ),
              ),
            ],
          ),
          data: (licences) {
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
            return ListView.separated(
              padding: const EdgeInsets.all(EqSpacing.md),
              itemCount: licences.length + 1,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: EqSpacing.sm),
              itemBuilder: (context, index) {
                if (index == 0) return const CompleteProfileBanner();
                final licence = licences[index - 1];
                return LicenceCard(
                  licence: licence,
                  typeLabel:
                      typeMap[licence.licenceType] ?? licence.licenceType,
                  onTap: () => context.go(Routes.licenceDetailFor(licence.id!)),
                  version: designVersion,
                );
              },
            );
          },
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
    final picked = await picker.pickImage(
      source: kIsWeb ? ImageSource.gallery : ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (picked == null || !context.mounted) return;

    final rawBytes = await picked.readAsBytes();

    // Strip EXIF on web before anything leaves the device. Mobile already
    // strips inside PhotoUpload at storage-write time, but the web OCR path
    // sends the image to an external Edge Function before storage — so we
    // strip up-front. Architecture §11.2.
    Uint8List bytes = rawBytes;
    if (kIsWeb) {
      try {
        bytes = await stripExifAndCompress(rawBytes);
      } catch (_) {
        // Strip failure shouldn't block OCR — fall through with raw bytes.
        bytes = rawBytes;
      }
    }

    OcrExtraction? extraction;
    try {
      final ocr = ref.read(ocrServiceProvider);
      extraction = kIsWeb
          ? await ocr.extractFromBytesViaEdgeFunction(bytes)
          : await ocr.extractFromFile(File(picked.path));
    } catch (_) {
      // OCR failure is non-fatal — fall through to manual edit with photo.
    }

    if (!context.mounted) return;
    context.go(
      Routes.licenceCreate,
      extra: LicencePrefill(photoBytes: bytes, ocr: extraction),
    );
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
          const Icon(
            Icons.badge_outlined,
            size: 64,
            color: EqColours.grey,
          ),
          const SizedBox(height: EqSpacing.md),
          Text(
            'No licences yet',
            style: EqTypography.headingL,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: EqSpacing.sm),
          Text(
            'Add your first licence — White Card, Driver Licence, First Aid, whatever you carry on site.',
            style: EqTypography.bodyM.copyWith(color: EqColours.grey),
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
