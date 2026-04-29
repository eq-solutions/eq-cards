import 'package:eq_cards/features/profile/presentation/notifiers/profile_notifier.dart';
import 'package:eq_cards/features/profile/profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake notifier returning a fixed Profile (or null) on build().
class _FakeProfileNotifier extends ProfileNotifier {
  _FakeProfileNotifier(this._initial);
  final Profile? _initial;

  @override
  Future<Profile?> build() async => _initial;
}

Profile _seed() => Profile(
      id: 'u1',
      fullName: 'Royce Milmlow',
      dateOfBirth: DateTime(1985, 1, 15),
      mobile: '+61412345678',
      email: 'royce@example.com',
      addressStreet: '123 King St',
      addressSuburb: 'Sydney',
      addressState: 'NSW',
      addressPostcode: '2000',
      emergencyContactName: 'Emma',
      emergencyContactRelationship: 'Spouse',
      emergencyContactMobile: '+61498765432',
    );

Future<void> _pump(WidgetTester tester, {Profile? initial}) async {
  // The ProfileEditScreen has 11 fields and is taller than the default
  // 800x600 test viewport. Without a larger surface the ListView lazy-builds
  // only what's visible and "Emergency contact" / "Emma" never render. Bump
  // the surface so all fields are constructed for the test.
  await tester.binding.setSurfaceSize(const Size(800, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        profileNotifierProvider
            .overrideWith(() => _FakeProfileNotifier(initial)),
      ],
      child: const MaterialApp(home: ProfileEditScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('ProfileEditScreen — render', () {
    testWidgets('renders title, sections, and Save button', (tester) async {
      await _pump(tester);
      expect(find.text('Edit profile'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
      expect(find.text('Address'), findsOneWidget);
      expect(find.text('Emergency contact'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('shows DOB placeholder when not yet set', (tester) async {
      await _pump(tester);
      expect(find.text('Select date of birth'), findsOneWidget);
    });
  });

  group('ProfileEditScreen — hydration', () {
    testWidgets('hydrates fields from existing profile', (tester) async {
      await _pump(tester, initial: _seed());
      expect(find.text('Royce Milmlow'), findsOneWidget);
      expect(find.text('+61412345678'), findsAtLeast(1));
      expect(find.text('royce@example.com'), findsOneWidget);
      expect(find.text('123 King St'), findsOneWidget);
      expect(find.text('Sydney'), findsOneWidget);
      expect(find.text('NSW'), findsOneWidget);
      expect(find.text('2000'), findsOneWidget);
      expect(find.text('Emma'), findsOneWidget);
      expect(find.text('Spouse'), findsOneWidget);
      expect(find.text('+61498765432'), findsOneWidget);
    });

    testWidgets('formats hydrated DOB as "d MMM yyyy"', (tester) async {
      await _pump(tester, initial: _seed());
      expect(find.text('15 Jan 1985'), findsOneWidget);
    });

    testWidgets('handles missing DOB on partial profile', (tester) async {
      final partial = _seed().copyWith(dateOfBirth: null);
      await _pump(tester, initial: partial);
      expect(find.text('Select date of birth'), findsOneWidget);
      expect(find.text('Royce Milmlow'), findsOneWidget);
    });
  });
}
