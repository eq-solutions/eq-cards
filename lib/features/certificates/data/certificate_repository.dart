import 'dart:typed_data';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/supabase/supabase_client_provider.dart';
import '../../../core/supabase/supabase_error_handler.dart';
import 'models/certificate.dart';

part 'certificate_repository.g.dart';

class CertificateRepository {
  CertificateRepository(this._client);
  final SupabaseClient _client;

  static const _bucket = 'certificates';
  static const _signedUrlSeconds = 3600;
  static const _table = 'certificates';

  String get _uid {
    final u = _client.auth.currentUser;
    if (u == null) throw const NotAuthenticatedFailure();
    return u.id;
  }

  Never _throw(Object e) => throw mapSupabaseError(e);

  Future<List<Certificate>> getAllForCurrentUser() async {
    final uid = _uid;
    try {
      final rows = await _client
          .from(_table)
          .select()
          .eq('user_id', uid)
          .eq('active', true)
          .order('created_at', ascending: false);
      final list = rows
          .map((r) => Certificate.fromJson(r))
          .toList();
      return Future.wait(list.map(_withSignedUrl));
    } catch (e) {
      _throw(e);
    }
  }

  Future<Certificate> insert(Certificate cert) async {
    final uid = _uid;
    try {
      final payload = _toPayload(cert, uid: uid);
      final row = await _client
          .from(_table)
          .insert(payload)
          .select()
          .single();
      return _withSignedUrl(
        Certificate.fromJson(row),
      );
    } catch (e) {
      _throw(e);
    }
  }

  Future<Certificate> update(Certificate cert) async {
    if (cert.id == null) throw const NotFoundFailure();
    final uid = _uid;
    try {
      final payload = _toPayload(cert, uid: uid);
      final row = await _client
          .from(_table)
          .update(payload)
          .eq('id', cert.id!)
          .eq('user_id', uid)
          .select()
          .single();
      return _withSignedUrl(
        Certificate.fromJson(row),
      );
    } catch (e) {
      _throw(e);
    }
  }

  Future<void> softDelete(String id) async {
    final uid = _uid;
    try {
      await _client
          .from(_table)
          .update({'active': false})
          .eq('id', id)
          .eq('user_id', uid);
    } catch (e) {
      _throw(e);
    }
  }

  /// Upload [bytes] to the certificates bucket.
  /// Returns the storage path to persist on the [Certificate] row.
  /// [ext] should be 'pdf', 'jpg', 'png', etc. (no leading dot).
  Future<String> uploadFile({
    required String certificateId,
    required String ext,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final uid = _uid;
    final path = '$uid/$certificateId.$ext';
    try {
      await _client.storage.from(_bucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: mimeType,
              upsert: true,
            ),
          );
      return path;
    } catch (e) {
      _throw(e);
    }
  }

  Future<void> deleteFile(String path) async {
    try {
      await _client.storage.from(_bucket).remove([path]);
    } catch (_) {
      // Best-effort — orphaned storage objects are not critical.
    }
  }

  Future<Certificate> _withSignedUrl(Certificate c) async {
    try {
      final url = await _client.storage
          .from(_bucket)
          .createSignedUrl(c.filePath, _signedUrlSeconds);
      return c.copyWith(fileSignedUrl: url);
    } catch (_) {
      return c;
    }
  }

  Map<String, dynamic> _toPayload(Certificate c, {required String uid}) {
    return <String, dynamic>{
      'user_id': uid,
      'title': c.title,
      'certificate_type': c.certificateType,
      if (c.issuer != null) 'issuer': c.issuer,
      if (c.issueDate != null) 'issue_date': _isoDate(c.issueDate!),
      if (c.expiryDate != null) 'expiry_date': _isoDate(c.expiryDate!),
      'file_path': c.filePath,
      'file_type': c.fileType,
      if (c.notes != null) 'notes': c.notes,
      'active': c.active,
    };
  }

  String _isoDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }
}

@riverpod
CertificateRepository certificateRepository(CertificateRepositoryRef ref) =>
    CertificateRepository(ref.watch(supabaseClientProvider));
