// Cards Unit 4 (2026-05-21) — storage path convention changed.
//
// Pre-canonical: paths were `{auth.uid()}/{licenceId}/{slot}.jpg`,
// where the first segment matched `auth.uid()` (Cards' own auth.user)
// and that's what the RLS checked.
//
// Post-canonical: the canonical licence-photos bucket RLS checks the
// first segment against `app_metadata.tenant_id`. Paths are now
// `{tenant_id}/{staff_id}/{licenceId}/{slot}.jpg` — tenant first for
// the RLS check, staff_id second so a future "all licences for a
// tenant" admin tool can prefix-list by tenant cleanly.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../error/failure.dart';
import '../supabase/supabase_client_provider.dart';

part 'photo_upload.g.dart';

/// Decode the JWT payload to extract claims that aren't surfaced via
/// `currentUser.appMetadata` — that field comes from
/// `auth.users.raw_app_meta_data` on the server, NOT from the JWT.
/// Our shell-minted JWT carries tenant_id in its app_metadata claim
/// but the auth.users row only has {"provider":"email"} — so we read
/// it directly from the token instead.
///
/// Returns null on any decode failure (malformed JWT, missing claim).
String? _tenantIdFromJwt(String? jwt) {
  if (jwt == null || jwt.isEmpty) return null;
  final parts = jwt.split('.');
  if (parts.length != 3) return null;
  try {
    var payload = parts[1];
    // base64url padding fix
    payload = payload.padRight(payload.length + (4 - payload.length % 4) % 4, '=');
    final decoded = utf8.decode(base64Url.decode(payload));
    final json = jsonDecode(decoded) as Map<String, dynamic>;
    final appMeta = json['app_metadata'] as Map<String, dynamic>?;
    return appMeta?['tenant_id'] as String?;
  } catch (_) {
    return null;
  }
}

class PhotoUpload {
  PhotoUpload(this._client);
  final SupabaseClient _client;

  static const _bucket = 'licence-photos';

  /// Mobile convenience overload — reads bytes from a `File` then delegates.
  Future<String> uploadLicencePhoto({
    required String licenceId,
    required String staffId,
    required String slot,
    required File source,
  }) async {
    final bytes = await source.readAsBytes();
    return uploadLicencePhotoBytes(
      licenceId: licenceId,
      staffId: staffId,
      slot: slot,
      bytes: bytes,
    );
  }

  /// Cross-platform path. Mobile and web both call this via bytes from
  /// `XFile.readAsBytes()`. The helper strips EXIF, resizes, and re-encodes.
  ///
  /// `staffId` is the canonical staff_id for the current user (resolved
  /// via the eq_cards_current_staff RPC at startup). It's passed in so
  /// the caller can decide whether to upload to "my staff" or (future)
  /// to an admin-elected staff_id without this helper re-querying every
  /// call.
  Future<String> uploadLicencePhotoBytes({
    required String licenceId,
    required String staffId,
    required String slot,
    required Uint8List bytes,
  }) async {
    // tenant_id lives in the JWT app_metadata, NOT in auth.users.
    // currentUser.appMetadata reads from auth.users.raw_app_meta_data
    // which we deliberately don't populate (the JWT is the truth).
    final tenantId =
        _tenantIdFromJwt(_client.auth.currentSession?.accessToken);
    if (tenantId == null || tenantId.isEmpty) {
      throw const NotAuthenticatedFailure();
    }

    final processed = await _stripExifAndCompress(bytes);
    final path = '$tenantId/$staffId/$licenceId/$slot.jpg';

    await _client.storage.from(_bucket).uploadBinary(
          path,
          processed,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );

    return path;
  }

  Future<String> signedUrl(String path) {
    return _client.storage.from(_bucket).createSignedUrl(path, 3600);
  }

  Future<Uint8List> _stripExifAndCompress(Uint8List input) =>
      stripExifAndCompress(input);
}

/// Decodes the image, strips ALL EXIF metadata (especially GPS), resizes
/// proportionally so neither dimension is below ~1080px, and re-encodes as
/// JPEG at quality 80. Architecture §11.2.
///
/// Used by:
/// - `PhotoUpload` before persisting to Supabase Storage.
/// - The web OCR path before sending to the `ocr-licence` Edge Function (so
///   the licence image never leaves the device with GPS metadata attached).
Future<Uint8List> stripExifAndCompress(Uint8List input) async {
  final result = await FlutterImageCompress.compressWithList(
    input,
    quality: 80,
    minWidth: 1080,
    minHeight: 1080,
    keepExif: false,
    format: CompressFormat.jpeg,
  );
  if (result.isEmpty) {
    throw const ServerFailure(0, 'Image compression failed');
  }
  return result;
}

@Riverpod(keepAlive: true)
PhotoUpload photoUpload(PhotoUploadRef ref) {
  return PhotoUpload(ref.watch(supabaseClientProvider));
}
