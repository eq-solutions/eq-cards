import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/error/user_messages.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../../core/utils/clipboard_utils.dart';
import '../../../../core/widgets/eq_app_bar.dart';
import '../../../../core/widgets/eq_button.dart';
import '../../../../core/widgets/eq_card.dart';
import '../../../../core/widgets/item_nav_bar.dart';
import '../../../licences/presentation/widgets/expiry_badge.dart';
import '../../data/models/certificate.dart';
import '../notifiers/certificates_list_notifier.dart';

class CertificateDetailScreen extends ConsumerWidget {
  const CertificateDetailScreen({super.key, required this.certificateId});

  final String certificateId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncCerts = ref.watch(certificatesListNotifierProvider);
    final allCerts = asyncCerts.asData?.value ?? [];
    final idx = allCerts.indexWhere((c) => c.id == certificateId);

    return Scaffold(
      appBar: EqAppBar(
        title: 'Document',
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: () =>
                context.go(Routes.certificateEditFor(certificateId)),
          ),
        ],
      ),
      bottomNavigationBar: allCerts.length > 1
          ? ItemNavBar(
              current: idx == -1 ? 1 : idx + 1,
              total: allCerts.length,
              onPrev: idx > 0
                  ? () => context.go(
                        Routes.certificateDetailFor(allCerts[idx - 1].id!),
                      )
                  : null,
              onNext: idx != -1 && idx < allCerts.length - 1
                  ? () => context.go(
                        Routes.certificateDetailFor(allCerts[idx + 1].id!),
                      )
                  : null,
            )
          : null,
      body: asyncCerts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(userMessageForError(e))),
        data: (certs) {
          final match = certs.where((c) => c.id == certificateId).toList();
          if (match.isEmpty) {
            return const Center(child: Text('Document not found.'));
          }
          return _CertificateDetailBody(
            cert: match.first,
            onDelete: () => _confirmDelete(context, ref, match.first),
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Certificate cert,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete document?'),
        content: Text(
          'This will remove "${cert.title}" from your wallet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: EqColours.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref
        .read(certificatesListNotifierProvider.notifier)
        .deleteCertificate(cert.id!);
    if (context.mounted) context.go(Routes.certificatesList);
  }
}

class _CertificateDetailBody extends StatelessWidget {
  const _CertificateDetailBody({
    required this.cert,
    required this.onDelete,
  });

  final Certificate cert;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('d MMMM yyyy');
    final typeLabel = certTypeLabels[cert.certificateType] ??
        cert.certificateType;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(EqSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header card ──────────────────────────────────────
          EqCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: EqColours.surface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        cert.isPdf
                            ? Icons.picture_as_pdf_outlined
                            : Icons.image_outlined,
                        color: EqColours.deep,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: EqSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InkWell(
                            onTap: () => unawaited(copyWithFeedback(context: context, value: cert.title, label: 'Title')),
                            borderRadius: BorderRadius.circular(4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    cert.title,
                                    style: EqTypography.headingM.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const Padding(
                                  padding: EdgeInsets.only(left: EqSpacing.xs, top: 2),
                                  child: Icon(
                                    Icons.copy_outlined,
                                    size: 16,
                                    color: EqColours.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: EqSpacing.xs),
                          Text(
                            typeLabel,
                            style: EqTypography.bodyM.copyWith(
                              color: EqColours.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: EqSpacing.md),

          // ── Details ──────────────────────────────────────────
          EqCard(
            child: Column(
              children: [
                if (cert.issuer != null)
                  _DetailRow(
                    label: 'Issuer',
                    value: cert.issuer!,
                    onTap: () => unawaited(copyWithFeedback(context: context, value: cert.issuer!, label: 'Issuer')),
                  ),
                if (cert.issueDate != null)
                  _DetailRow(
                    label: 'Issued',
                    value: dateFmt.format(cert.issueDate!),
                  ),
                if (cert.expiryDate != null)
                  _DetailRow(
                    label: 'Expires',
                    value: dateFmt.format(cert.expiryDate!),
                    trailing: ExpiryBadge(expiry: cert.expiryDate!),
                  ),
                if (cert.notes != null)
                  _DetailRow(label: 'Notes', value: cert.notes!),
              ],
            ),
          ),
          const SizedBox(height: EqSpacing.lg),

          // ── Open file ────────────────────────────────────────
          EqButton(
            label: cert.isPdf ? 'Open PDF' : 'View image',
            onPressed: cert.fileSignedUrl != null
                ? () => _openFile(context, cert)
                : null,
            fullWidth: true,
          ),
          const SizedBox(height: EqSpacing.xl),

          // ── Delete ───────────────────────────────────────────
          TextButton(
            onPressed: onDelete,
            child: Text(
              'Delete document',
              style: EqTypography.bodyM.copyWith(color: EqColours.error),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openFile(BuildContext context, Certificate cert) async {
    if (cert.fileSignedUrl == null) return;

    if (cert.isPdf) {
      final uri = Uri.parse(cert.fileSignedUrl!);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } else {
      // Show image full-screen.
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.black,
          insetPadding: EdgeInsets.zero,
          child: Stack(
            children: [
              InteractiveViewer(
                child: Image.network(
                  cert.fileSignedUrl!,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Center(
                    child: Icon(Icons.broken_image, color: Colors.white54),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.trailing,
    this.onTap,
  });

  final String label;
  final String value;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: EqSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: EqTypography.label.copyWith(color: EqColours.grey),
            ),
          ),
          const SizedBox(width: EqSpacing.md),
          Expanded(
            child: Text(
              value,
              style: EqTypography.bodyM.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
          ?trailing,
          if (onTap != null)
            const Padding(
              padding: EdgeInsets.only(left: EqSpacing.sm),
              child: Icon(Icons.copy_outlined, size: 16, color: EqColours.grey),
            ),
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: content,
    );
  }
}
