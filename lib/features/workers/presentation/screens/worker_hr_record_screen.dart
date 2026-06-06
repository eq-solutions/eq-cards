import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../../core/widgets/eq_app_bar.dart';
import '../../../../core/widgets/eq_card.dart';
import '../../data/worker_self_repository.dart';

/// Read-only view of the workers record held by the organisation.
///
/// Australian Privacy Principles (APP 12) require that individuals can access
/// personal information an organisation holds about them. This screen satisfies
/// that requirement for the workers table (the org's HR record).
///
/// Workers cannot edit here — corrections go to the admin for v1.
class WorkerHrRecordScreen extends ConsumerWidget {
  const WorkerHrRecordScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: const EqAppBar(title: 'My employment record'),
      body: FutureBuilder<Worker?>(
        future: ref.read(workerSelfRepositoryProvider).getHrRecord(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: EqColours.sky),
            );
          }
          if (snap.hasError) {
            return Center(
              child: Text(
                'Could not load record.',
                style: EqTypography.bodyM.copyWith(color: EqColours.grey),
              ),
            );
          }
          final worker = snap.data;
          if (worker == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(EqSpacing.xl),
                child: Text(
                  'No employment record found.\n\n'
                  'This appears once your employer has added you to EQ Cards '
                  'and you have claimed your invite.',
                  style: EqTypography.bodyM.copyWith(color: EqColours.grey),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return _RecordView(worker: worker);
        },
      ),
    );
  }
}

class _RecordView extends StatelessWidget {
  const _RecordView({required this.worker});

  final Worker worker;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(EqSpacing.md),
      children: [
        _Section(
          label: 'Personal',
          children: [
            _Row('Name', worker.displayName),
            if (worker.phone != null) _Row('Mobile', worker.phone!),
            if (worker.email != null) _Row('Email', worker.email!),
            if (worker.dateOfBirth != null)
              _Row('Date of birth', _formatDate(worker.dateOfBirth!)),
          ],
        ),
        if (_hasAddress(worker)) ...[
          const SizedBox(height: EqSpacing.lg),
          _Section(
            label: 'Address',
            children: [
              if (worker.addressStreet != null)
                _Row('Street', worker.addressStreet!),
              if (worker.addressSuburb != null)
                _Row('Suburb', worker.addressSuburb!),
              if (worker.addressState != null)
                _Row('State', worker.addressState!),
              if (worker.addressPostcode != null)
                _Row('Postcode', worker.addressPostcode!),
            ],
          ),
        ],
        if (_hasEmergencyContact(worker)) ...[
          const SizedBox(height: EqSpacing.lg),
          _Section(
            label: 'Emergency contact',
            children: [
              if (worker.emergencyContactName != null)
                _Row('Name', worker.emergencyContactName!),
              if (worker.emergencyContactPhone != null)
                _Row('Mobile', worker.emergencyContactPhone!),
              if (worker.emergencyContactRelationship != null)
                _Row('Relationship', worker.emergencyContactRelationship!),
            ],
          ),
        ],
        if (worker.rightToWorkType != null) ...[
          const SizedBox(height: EqSpacing.lg),
          _Section(
            label: 'Right to work',
            children: [
              _Row('Type', worker.rightToWorkType!),
              if (worker.rightToWorkExpiry != null)
                _Row('Expiry', _formatDate(worker.rightToWorkExpiry!)),
            ],
          ),
        ],
        const SizedBox(height: EqSpacing.xl),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: EqSpacing.sm),
          child: Text(
            'This information is held by your employer. To correct any '
            'inaccurate details, contact your admin directly.',
            style: EqTypography.label.copyWith(color: EqColours.grey),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: EqSpacing.xl),
      ],
    );
  }

  bool _hasAddress(Worker w) =>
      w.addressStreet != null ||
      w.addressSuburb != null ||
      w.addressState != null ||
      w.addressPostcode != null;

  bool _hasEmergencyContact(Worker w) =>
      w.emergencyContactName != null ||
      w.emergencyContactPhone != null ||
      w.emergencyContactRelationship != null;

  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: EqSpacing.xs, bottom: EqSpacing.sm),
          child: Text(label, style: EqTypography.label),
        ),
        EqCard(
          padding: const EdgeInsets.all(EqSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: EqSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: EqTypography.label),
          ),
          Expanded(child: Text(value, style: EqTypography.bodyM)),
        ],
      ),
    );
  }
}
