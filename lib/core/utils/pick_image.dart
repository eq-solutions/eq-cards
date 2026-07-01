import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Picks an image, offering camera or gallery choice on web.
///
/// On native (non-web) goes straight to the rear camera — unchanged behaviour.
/// On web (PWA), shows a bottom sheet so mobile users can tap "Take a photo"
/// rather than being dropped straight into their photo library.
/// Desktop web users see the same sheet; both options open a file picker there
/// (browsers ignore the capture attribute on desktop), which is fine.
Future<XFile?> pickImageWithSourceChoice(
  BuildContext context,
  ImagePicker picker, {
  int? imageQuality,
}) async {
  if (!kIsWeb) {
    return picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
      imageQuality: imageQuality,
    );
  }

  if (!context.mounted) return null;
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from library'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null) return null;
  return picker.pickImage(
    source: source,
    preferredCameraDevice: CameraDevice.rear,
    imageQuality: imageQuality,
  );
}
