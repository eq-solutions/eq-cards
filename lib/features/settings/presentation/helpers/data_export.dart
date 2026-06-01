import 'dart:convert';

import '../../../../core/utils/date_utils.dart';
import '../../../licences/data/models/licence.dart';
import '../../../profile/data/models/profile.dart';

/// Builds a JSON-serialisable map of the user's wallet — profile + licences
/// — for the "Export my data" action in Settings. Honours the access right
/// guaranteed in the Privacy Policy §9.
///
/// Output structure is stable and documented at the top of the result so
/// future versions can rev cleanly without breaking consumers (the user, or
/// us when we re-import).
Map<String, dynamic> buildExportPayload({
  required Profile? profile,
  required List<Licence> licences,
  required DateTime now,
}) {
  return <String, dynamic>{
    '_format': 'eq-cards-export',
    '_format_version': 1,
    '_generated_at': now.toUtc().toIso8601String(),
    '_notes':
        'This is a copy of every personal-data field EQ Cards holds about '
            'you. Photos are referenced by signed-URL only — those links '
            'expire after one hour. To preserve the photos, download them '
            "before the link expires. See EQ's Privacy Policy section 9.",
    'profile': profile == null ? null : _profileMap(profile),
    'licences': licences.map(_licenceMap).toList(),
  };
}

/// Convenience: serialise the payload with 2-space indentation.
String exportPayloadToJsonString(Map<String, dynamic> payload) {
  return const JsonEncoder.withIndent('  ').convert(payload);
}

Map<String, dynamic> _profileMap(Profile p) {
  return <String, dynamic>{
    'id': p.id,
    'full_name': p.fullName,
    'date_of_birth': _isoDate(p.dateOfBirth),
    'mobile': p.mobile,
    'email': p.email,
    'address': {
      'street': p.addressStreet,
      'suburb': p.addressSuburb,
      'state': p.addressState,
      'postcode': p.addressPostcode,
    },
    'emergency_contact': {
      'name': p.emergencyContactName,
      'relationship': p.emergencyContactRelationship,
      'mobile': p.emergencyContactMobile,
    },
  };
}

Map<String, dynamic> _licenceMap(Licence l) {
  return <String, dynamic>{
    'id': l.id,
    'licence_type': l.licenceType,
    'licence_number': l.licenceNumber,
    'issue_date': _isoDate(l.issueDate),
    'expiry_date': _isoDate(l.expiryDate),
    'issuing_authority': l.issuingAuthority,
    'state': l.state,
    'notes': l.notes,
    'metadata': l.metadata,
    'photo_front_signed_url': l.photoFrontSignedUrl,
    'photo_back_signed_url': l.photoBackSignedUrl,
  };
}

/// Nullable wrapper around [EqDates.iso] for the optional date fields in the
/// export payload (a null date stays null rather than throwing).
String? _isoDate(DateTime? d) => d == null ? null : EqDates.iso(d);
