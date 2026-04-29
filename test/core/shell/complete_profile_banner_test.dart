import 'package:eq_cards/core/router/routes.dart';
import 'package:eq_cards/core/shell/complete_profile_banner.dart';
import 'package:eq_cards/features/profile/presentation/notifiers/profile_notifier.dart';
import 'package:eq_cards/features/profile/profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Fake notifier that just returns a fixed Profile (or null) on build().
class _FakeProfileNotifier extends ProfileNotifier {
  _FakeProfileNotifier(this._value);
  final Profile? _value;

  @override
  Future<Profile?> build() async => _value;
}

GoRouter _router() => GoRouter(
      initialLocation: Routes.licencesList,
      routes: [
        GoRoute(
          path: Routes.licencesList,
          builder: (context, state) => const Scaffold(
            body: SafeArea(child: CompleteProfileBanner()),
          ),
        ),
        GoRoute(
          path: Routes.profileEdit,
          builder: (context, state) => const Scaffold(
            body: Center(child: Text('PROFILE_EDIT_DEST')),
          ),
        ),
      ],
    );

Profile _completeProfile() => Profile(
      id: 'u1',
      fullName: 'Royce Milmlow',
      dateOfBirth: DateTime(1985, 1, 15),
      mobile: '+61412345678',
      addressStreet: '123 King St',
      addressSuburb: 'Sydney',
      addressState: 'NSW',
      addressPostcode: '2000',
      emergencyContactName: 'Emma',
      emergencyContactMobile: '+61498765432',
    );

Future<void> _pump(WidgetTester tester, Profile? profile) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        profileNotifierProvider
            .overrideWith(() => _FakeProfileNotifier(profile)),
      ],
      child: MaterialApp.router(routerConfig: _router()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('CompleteProfileBanner', () {
    testWidgets('hidden when profile is complete', (tester) async {
      await _pump(tester, _completeProfile());
      expect(find.text('Complete your profile'), findsNothing);
    });

    testWidgets('shown when profile is null', (tester) async {
      await _pump(tester, null);
      expect(find.text('Complete your profile'), findsOneWidget);
    });

    testWidgets('shown when profile is incomplete (DOB missing)',
        (tester) async {
      final partial = _completeProfile().copyWith(dateOfBirth: null);
      await _pump(tester, partial);
      expect(find.text('Complete your profile'), findsOneWidget);
    });

    testWidgets('shown when profile missing emergency contact',
        (tester) async {
      final partial = _completeProfile().copyWith(emergencyContactName: null);
      await _pump(tester, partial);
      expect(find.text('Complete your profile'), findsOneWidget);
    });

    testWidgets('Finish button navigates to /profile/edit',
        (tester) async {
      await _pump(tester, null);
      expect(find.text('Finish'), findsOneWidget);
      await tester.tap(find.text('Finish'));
      await tester.pumpAndSettle();
      expect(find.text('PROFILE_EDIT_DEST'), findsOneWidget);
    });
  });
}
