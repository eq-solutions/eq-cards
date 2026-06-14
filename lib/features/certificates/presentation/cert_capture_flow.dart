import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../../core/router/routes.dart';
import '../../../core/utils/photo_upload.dart';
import '../../../core/widgets/ocr_loading_dialog.dart';
import '../../licences/data/ocr_service.dart';
import '../../licences/presentation/helpers/licence_crop.dart';
import '../../licences/presentation/screens/licence_crop_screen.dart';
import 'screens/certificate_add_screen.dart' show CertPrefill;

/// Types that map to certificates (vs. licences) in the OCR extraction.
const certTypeSet = {
  'white_card',
  'first_aid',
  'lv_cpr',
  'working_at_heights',
  'confined_space',
  'boom_ewp',
  'forklift',
  'dogman',
  'rigger',
};

/// Pick/crop/OCR a certificate photo and navigate to the cert create screen
/// with pre-populated fields. Returns without navigating if the user cancels
/// at any step.
Future<void> certCaptureFlow(BuildContext context, WidgetRef ref) async {
  final picker = ImagePicker();
  final picked = await picker.pickImage(
    source: kIsWeb ? ImageSource.gallery : ImageSource.camera,
    preferredCameraDevice: CameraDevice.rear,
    imageQuality: 85,
  );
  if (picked == null || !context.mounted) return;

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
    if (cropped == null || !context.mounted) return;
    rawBytes = cropped;
  } else {
    final c = await cropLicencePhoto(context, picked, actionLabel: 'Use photo');
    if (c == null || !context.mounted) return;
    croppedFile = c;
    rawBytes = await c.readAsBytes();
  }

  if (!context.mounted) return;
  final loadingDialog = showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const OcrLoadingDialog(noun: 'certificate'),
  );

  var bytes = rawBytes;
  const mime = 'image/jpeg';
  if (kIsWeb) {
    try {
      bytes = await stripExifAndCompress(rawBytes);
    } catch (_) {}
  }

  OcrExtraction? extraction;
  var cancelled = false;
  final ocr = ref.read(ocrServiceProvider);
  final ocrCall = (kIsWeb || croppedFile == null
          ? ocr.extractFromBytesViaEdgeFunction(bytes, mimeType: mime)
          : ocr.extractFromFile(File(croppedFile.path)))
      .then<void>((r) => extraction = r)
      .catchError((Object e, StackTrace st) {
    unawaited(Sentry.captureException(e, stackTrace: st));
  });

  final cancelCall = loadingDialog
      .then<void>((result) { if (result ?? false) cancelled = true; });
  await Future.any<void>([ocrCall, cancelCall]);

  if (!cancelled) {
    try {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    } catch (_) {}
  }
  unawaited(loadingDialog);
  unawaited(ocrCall);
  if (!context.mounted) return;

  final ocrType = extraction?.licenceTypeCandidate;
  final certType =
      (!cancelled && ocrType != null && certTypeSet.contains(ocrType))
          ? ocrType
          : null;

  context.go(
    Routes.certificateCreate,
    extra: CertPrefill(
      photoBytes: bytes,
      expiryDate: cancelled ? null : extraction?.expiryDateCandidate,
      suggestedType: certType,
    ),
  );
}
