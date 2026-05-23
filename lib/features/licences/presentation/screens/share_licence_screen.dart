import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';

// Data returned by the share-licence edge function.
class _ShareData {
  const _ShareData({
    required this.licenceType,
    required this.licenceNumber,
    this.state,
    this.issuingAuthority,
    required this.expiryDate,
    this.holderName,
  });

  factory _ShareData.fromJson(Map<String, dynamic> json) => _ShareData(
        licenceType: json['licence_type'] as String,
        licenceNumber: json['licence_number'] as String,
        state: json['state'] as String?,
        issuingAuthority: json['issuing_authority'] as String?,
        expiryDate: json['expiry_date'] as String,
        holderName: json['holder_name'] as String?,
      );

  final String licenceType;
  final String licenceNumber;
  final String? state;
  final String? issuingAuthority;
  final String expiryDate; // YYYY-MM-DD from the API
  final String? holderName;
}

// Minimal label map matching the seeded licence_types codes.
// Custom types fall back to title-casing the code.
const _typeLabels = <String, String>{
  'white_card': 'White Card',
  'driver_licence': 'Driver Licence',
  'first_aid': 'First Aid Certificate',
  'cpr': 'CPR Certificate',
  'working_at_heights': 'Working at Heights',
  'confined_space': 'Confined Space',
  'ewp': 'Elevated Work Platform',
  'forklift_hrwl': 'Forklift (HRWL)',
  'test_and_tag': 'Test and Tag',
  'electrical_licence': 'Electrical Licence',
  'medicare': 'Medicare Card',
  'asbestos_awareness': 'Asbestos Awareness',
  'traffic_control': 'Traffic Control',
};

String _labelFor(String code) =>
    _typeLabels[code] ??
    code.split('_').map((w) => '${w[0].toUpperCase()}${w.substring(1)}').join(' ');

String _formatDate(String yyyyMmDd) {
  try {
    final dt = DateTime.parse(yyyyMmDd);
    return DateFormat('d MMM yyyy').format(dt);
  } catch (_) {
    return yyyyMmDd;
  }
}

bool _isExpired(String yyyyMmDd) {
  try {
    return DateTime.parse(yyyyMmDd).isBefore(DateTime.now());
  } catch (_) {
    return false;
  }
}

/// Public, no-auth screen — displays a read-only verification card for a
/// shared licence. Reached by scanning the QR code from LicenceDetailScreen.
///
/// URL: /share?licence_id=<uuid>
class ShareLicenceScreen extends StatelessWidget {
  const ShareLicenceScreen({super.key, required this.licenceId});

  final String licenceId;

  Future<_ShareData> _fetch() async {
    const baseUrl = String.fromEnvironment('SUPABASE_URL');
    const url = '$baseUrl/functions/v1/share-licence';
    final response = await Dio().get<Map<String, dynamic>>(
      url,
      queryParameters: {'licence_id': licenceId},
      options: Options(
        validateStatus: (_) => true,
        receiveTimeout: const Duration(seconds: 12),
      ),
    );

    if (response.statusCode == 404) {
      throw const _LicenceNotFoundError();
    }
    if (response.statusCode != 200 || response.data == null) {
      throw Exception('Failed to load licence (${response.statusCode})');
    }
    return _ShareData.fromJson(response.data!);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EqColours.white,
      body: SafeArea(
        child: FutureBuilder<_ShareData>(
          future: _fetch(),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                child: CircularProgressIndicator(color: EqColours.sky),
              );
            }
            if (snapshot.hasError) {
              final isNotFound = snapshot.error is _LicenceNotFoundError;
              return _ErrorBody(
                message: isNotFound
                    ? 'This licence could not be found.'
                    : 'Something went wrong. Please try again.',
              );
            }
            return _VerificationBody(data: snapshot.data!);
          },
        ),
      ),
    );
  }
}

class _VerificationBody extends StatelessWidget {
  const _VerificationBody({required this.data});

  final _ShareData data;

  @override
  Widget build(BuildContext context) {
    final expired = _isExpired(data.expiryDate);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: EqSpacing.lg,
        vertical: EqSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Brand header
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: EqColours.sky,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.badge_outlined, color: EqColours.white, size: 22),
              ),
              const SizedBox(width: EqSpacing.sm),
              Text('EQ Cards', style: EqTypography.headingM.copyWith(color: EqColours.sky)),
            ],
          ),
          const SizedBox(height: EqSpacing.xl),

          // Verification card
          Container(
            decoration: BoxDecoration(
              color: EqColours.white,
              border: Border.all(color: EqColours.border),
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(EqSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Verified badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: EqSpacing.sm,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: expired ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        expired ? Icons.warning_amber_outlined : Icons.verified_outlined,
                        size: 14,
                        color: expired ? EqColours.error : EqColours.success,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        expired ? 'Expired' : 'Verified',
                        style: EqTypography.label.copyWith(
                          color: expired ? EqColours.error : EqColours.success,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: EqSpacing.md),

                // Licence type
                Text(
                  _labelFor(data.licenceType),
                  style: EqTypography.headingL,
                ),
                if (data.holderName != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    data.holderName!,
                    style: EqTypography.bodyL.copyWith(color: EqColours.grey),
                  ),
                ],

                const SizedBox(height: EqSpacing.lg),
                const Divider(color: Color(0xFFE5E7EB), height: 1),
                const SizedBox(height: EqSpacing.lg),

                // Detail rows
                _Row(label: 'Licence number', value: data.licenceNumber),
                if (data.state != null)
                  _Row(label: 'State', value: data.state!),
                if (data.issuingAuthority != null)
                  _Row(label: 'Issuing authority', value: data.issuingAuthority!),
                _Row(
                  label: 'Expiry',
                  value: _formatDate(data.expiryDate),
                  valueColor: expired ? EqColours.error : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: EqSpacing.xl),

          // Footer
          Text(
            'Shared via EQ Cards · the tradie licence wallet',
            textAlign: TextAlign.center,
            style: EqTypography.label.copyWith(color: EqColours.grey),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: EqSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: EqTypography.label,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: EqTypography.bodyM.copyWith(
                color: valueColor ?? EqColours.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(EqSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: EqColours.grey),
            const SizedBox(height: EqSpacing.md),
            Text(message, textAlign: TextAlign.center, style: EqTypography.bodyM),
          ],
        ),
      ),
    );
  }
}

class _LicenceNotFoundError implements Exception {
  const _LicenceNotFoundError();
}
