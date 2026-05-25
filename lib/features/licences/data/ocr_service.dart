import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'ocr_service.g.dart';

class OcrExtraction {
  const OcrExtraction({
    required this.rawText,
    required this.lines,
    this.numberCandidate,
    this.licenceTypeCandidate,
    this.issuingAuthorityCandidate,
    this.stateCandidate,
    this.issueDateCandidate,
    this.expiryDateCandidate,
    // Driver licence profile fields — non-null only when licenceTypeCandidate
    // is 'driver_licence' and the field was legible.
    this.holderName,
    this.dateOfBirth,
    this.addressStreet,
    this.addressSuburb,
    this.addressState,
    this.addressPostcode,
  });

  final String rawText;
  final List<String> lines;
  final String? numberCandidate;
  final String? licenceTypeCandidate;
  final String? issuingAuthorityCandidate;
  final String? stateCandidate;
  final DateTime? issueDateCandidate;
  final DateTime? expiryDateCandidate;

  // Profile fields — only populated for driver licences.
  final String? holderName;
  final DateTime? dateOfBirth;
  final String? addressStreet;
  final String? addressSuburb;
  final String? addressState;
  final String? addressPostcode;

  /// True when at least one profile field was extracted — used to decide
  /// whether to show the "Fill your profile from this scan?" confirmation
  /// step after a driver licence scan.
  bool get hasProfileFields =>
      holderName != null ||
      dateOfBirth != null ||
      addressStreet != null ||
      addressSuburb != null ||
      addressState != null ||
      addressPostcode != null;
}

class OcrService {
  OcrService(this._supabase);

  final SupabaseClient _supabase;

  /// Lazy-init so we never construct the recognizer on web (where the
  /// underlying ML Kit plugin doesn't exist). Architecture §11.5.
  TextRecognizer? _recognizer;

  /// Mobile path: on-device ML Kit OCR + regex post-processing.
  Future<OcrExtraction> extractFromFile(File file) async {
    if (kIsWeb) {
      return const OcrExtraction(rawText: '', lines: []);
    }
    final recognizer = _recognizer ??= TextRecognizer();
    final input = InputImage.fromFile(file);
    final recognized = await recognizer.processImage(input);
    final lines = <String>[];
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        lines.add(line.text);
      }
    }

    final dates = findDatesInText(recognized.text);
    final number = findLicenceNumberInLines(lines);

    DateTime? issue;
    DateTime? expiry;
    if (dates.length >= 2) {
      dates.sort();
      issue = dates.first;
      expiry = dates.last;
    } else if (dates.length == 1) {
      // Single date — assume expiry (more often printed prominently).
      expiry = dates.first;
    }

    return OcrExtraction(
      rawText: recognized.text,
      lines: lines,
      numberCandidate: number,
      issueDateCandidate: issue,
      expiryDateCandidate: expiry,
    );
  }

  /// Web path: POST the image to the `ocr-licence` Supabase Edge Function,
  /// which calls Anthropic Claude Vision and returns structured fields.
  /// Architecture §16 Q3 (revised 2026-04-28).
  ///
  /// Retries once on transient errors (5xx, timeout, network) with a 1.5s
  /// backoff. Does NOT retry on 4xx — those are client-side issues
  /// (unauthorized, bad request, unsupported mime) where retrying won't
  /// help and would just delay the user-visible error.
  Future<OcrExtraction> extractFromBytesViaEdgeFunction(
    Uint8List bytes, {
    String mimeType = 'image/jpeg',
  }) async {
    final body = {
      'image_base64': base64Encode(bytes),
      'mime_type': mimeType,
    };

    // Single retry policy — total time budget capped at ~32s so the
    // non-dismissable loading dialog can't trap the user for 93s in the
    // worst case (which the old compound-retry path could reach).
    Future<FunctionResponse> invoke() => _supabase.functions
        .invoke('ocr-licence', body: body)
        .timeout(const Duration(seconds: 14));

    FunctionResponse response;
    var retried = false;
    try {
      response = await invoke();
    } catch (e) {
      // Transient — single retry attempt.
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      retried = true;
      response = await invoke();
    }

    // Only retry on 5xx if we haven't already retried after a thrown
    // error. 4xx is client-side — never retry. Cap at one total retry.
    if (response.status != 200 && !retried) {
      final s = response.status;
      if (s >= 500 && s < 600) {
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        response = await invoke();
      }
    }
    if (response.status != 200) {
      throw Exception(
        'ocr-licence failed: ${response.status} ${response.data}',
      );
    }
    final data = response.data as Map<String, dynamic>;
    final rawText = (data['raw_text'] as String?) ?? '';
    return OcrExtraction(
      rawText: rawText,
      lines: rawText.split('\n'),
      numberCandidate: data['licence_number'] as String?,
      licenceTypeCandidate: data['licence_type'] as String?,
      issuingAuthorityCandidate: data['issuing_authority'] as String?,
      stateCandidate: data['state'] as String?,
      issueDateCandidate: _parseIsoDate(data['issue_date'] as String?),
      expiryDateCandidate: _parseIsoDate(data['expiry_date'] as String?),
      // Driver licence profile fields — null for all other document types.
      holderName: data['holder_name'] as String?,
      dateOfBirth: _parseIsoDate(data['date_of_birth'] as String?),
      addressStreet: data['address_street'] as String?,
      addressSuburb: data['address_suburb'] as String?,
      addressState: data['address_state'] as String?,
      addressPostcode: data['address_postcode'] as String?,
    );
  }

  static DateTime? _parseIsoDate(String? s) {
    if (s == null || s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  void dispose() => _recognizer?.close();
}

/// Finds dates in raw OCR text. Recognises numeric formats common on Aussie
/// licences: `dd/mm/yyyy`, `dd-mm-yyyy`, `dd.mm.yyyy`. Two-digit years are
/// expanded into the 2000s.
@visibleForTesting
List<DateTime> findDatesInText(String text) {
  final pattern = RegExp(r'\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})\b');
  final results = <DateTime>[];
  for (final match in pattern.allMatches(text)) {
    final d = int.tryParse(match.group(1)!);
    final m = int.tryParse(match.group(2)!);
    var y = int.tryParse(match.group(3)!);
    if (d == null || m == null || y == null) continue;
    if (y < 100) y += 2000;
    if (m < 1 || m > 12 || d < 1 || d > 31) continue;
    try {
      results.add(DateTime(y, m, d));
    } catch (_) {
      continue;
    }
  }
  return results;
}

/// Finds the most likely licence number from OCR'd lines. Walks the text in
/// two passes:
///
/// 1. Aussie-specific patterns we recognise unambiguously:
///    - HLTAID codes (First Aid units of competency, e.g. `HLTAID011`)
///    - Lines that label the number explicitly (`LICENCE NO 12345678`,
///      `CARD NUMBER ABC12345`, `NUMBER: 87654321`)
///
/// 2. Bare 6–12-character alphanumeric strings, filtered to exclude things
///    that look like compact `YYYYMMDD` dates or pure-letter words.
///
/// White Card numbers (typically 8 digits) survive the date filter because
/// they don't start with `19xx` or `20xx`.
@visibleForTesting
String? findLicenceNumberInLines(List<String> lines) {
  // Pass 1 — explicit patterns.
  for (final line in lines) {
    final stripped = line.replaceAll(RegExp(r'\s+'), '').toUpperCase();

    // HLTAID first-aid codes. No leading `\b` because after whitespace stripping
    // the code may sit between word chars (e.g. `UNITCODEHLTAID009-CPR`).
    final hltaid = RegExp(r'HLTAID\d+').firstMatch(stripped);
    if (hltaid != null) return hltaid.group(0);

    // Labelled lines: LICENCE NO / CARD NO / NUMBER / NO. / # → grab the value.
    // Allows chained labels (`LICENCE NO`, `CARD NUMBER`) so the inner stop-word
    // doesn't get captured as part of the value.
    final labelled = RegExp(
      r'(?:(?:LICENCE|LIC|CARD|NUMBER|NO|#)[:.\s]*)+([A-Z0-9]{6,12})',
    ).firstMatch(stripped);
    if (labelled != null) {
      final candidate = labelled.group(1)!;
      if (!_looksLikeCompactDate(candidate)) return candidate;
    }
  }

  // Pass 2 — bare alphanumeric strings, with smarter date filtering.
  // Licence numbers always contain digits; pure-letter words like `ISSUEDATE`
  // are rejected here so they don't false-positive as the licence number.
  for (final line in lines) {
    final stripped = line.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    if (!RegExp(r'^[A-Z0-9]{6,12}$').hasMatch(stripped)) continue;
    if (!stripped.contains(RegExp(r'\d'))) continue;
    if (_looksLikeCompactDate(stripped)) continue;
    return stripped;
  }
  return null;
}

/// True when an 8-digit string looks like a `YYYYMMDD` compact date in the
/// 19xx or 20xx range. Other digit lengths and digit prefixes are not dates,
/// so White Card numbers (8 digits, no year prefix) survive.
bool _looksLikeCompactDate(String s) {
  if (s.length != 8 || !RegExp(r'^\d{8}$').hasMatch(s)) return false;
  final year = int.tryParse(s.substring(0, 4));
  if (year == null) return false;
  return year >= 1900 && year <= 2099;
}

@Riverpod(keepAlive: true)
OcrService ocrService(OcrServiceRef ref) {
  final service = OcrService(Supabase.instance.client);
  ref.onDispose(service.dispose);
  return service;
}
