import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../../../core/theme/eq_colours.dart';

/// Opens the EQ-branded image cropper on a picked file. Returns the cropped
/// `XFile`, the original picked file if the cropper widget threw, or `null`
/// if the user cancelled.
///
/// Shared between the OCR-scan flow (list screen) and the photo-replace flow
/// (edit screen) so both produce consistently framed, ~85% JPEG-quality
/// photos. The action button is labelled "Scan licence" on the OCR path
/// (passed via [actionLabel]) and "Use photo" elsewhere — same widget, same
/// branded chrome, different verb so the user knows what tapping it does.
Future<XFile?> cropLicencePhoto(
  BuildContext context,
  XFile picked, {
  required String actionLabel,
}) async {
  // Web uses LicenceCropScreen (pure Flutter, no JS bridge). This function
  // should never be called on web — callers guard with kIsWeb checks.
  assert(!kIsWeb, 'cropLicencePhoto called on web — use LicenceCropScreen');
  if (kIsWeb) return picked;

  try {
    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      // ID-1 card aspect ratio (CR80, ISO/IEC 7810) suits most licences.
      // User can override.
      aspectRatio: const CropAspectRatio(ratioX: 1.586, ratioY: 1),
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 85,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Frame your licence',
          toolbarColor: EqColours.sky,
          toolbarWidgetColor: EqColours.white,
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
        ),
        IOSUiSettings(
          title: 'Frame your licence',
          doneButtonTitle: actionLabel,
          cancelButtonTitle: 'Cancel',
        ),
        WebUiSettings(
          context: context,
          presentStyle: WebPresentStyle.dialog,
          size: const CropperSize(width: 520, height: 380),
          translations: WebTranslations(
            title: 'Frame your licence',
            rotateLeftTooltip: 'Rotate left',
            rotateRightTooltip: 'Rotate right',
            cancelButton: 'Cancel',
            cropButton: actionLabel,
          ),
        ),
      ],
    );
    if (cropped == null) return null;
    return XFile(cropped.path);
  } catch (e, st) {
    // Cropper failure shouldn't block the flow — fall through with the
    // original picked file so the user can still save / scan / continue.
    unawaited(Sentry.captureException(e, stackTrace: st));
    return picked;
  }
}
