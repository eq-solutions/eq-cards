import 'package:eq_cards/core/cards_api/cards_data_source_providers.dart';
import 'package:eq_cards/core/error/failure.dart';
import 'package:eq_cards/core/supabase/supabase_error_handler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal stand-in for a [CardsDataSource]; identity is all the transport
/// switch test cares about, so the methods are never called.
class _FakeCardsDataSource implements CardsDataSource {
  @override
  Future<Map<String, dynamic>?> currentStaff() => throw UnimplementedError();

  @override
  Future<List<Map<String, dynamic>>> listMyLicences() =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> upsertMyLicence(Map<String, dynamic> payload) =>
      throw UnimplementedError();

  @override
  Future<void> softDeleteMyLicence(String licenceId) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> upsertMyProfile(Map<String, dynamic> payload) =>
      throw UnimplementedError();
}

void main() {
  group('cardsDataTransportFromString', () {
    test('maps "gateway" to gateway', () {
      expect(
        cardsDataTransportFromString('gateway'),
        CardsDataTransport.gateway,
      );
    });

    test('maps "direct" to direct', () {
      expect(cardsDataTransportFromString('direct'), CardsDataTransport.direct);
    });

    test('defaults the empty string to direct', () {
      expect(cardsDataTransportFromString(''), CardsDataTransport.direct);
    });

    test('is case-sensitive and fail-safe ("GATEWAY" -> direct)', () {
      expect(
        cardsDataTransportFromString('GATEWAY'),
        CardsDataTransport.direct,
      );
    });

    test('maps any unknown value to direct', () {
      expect(
        cardsDataTransportFromString('garbage'),
        CardsDataTransport.direct,
      );
    });
  });

  group('cardsDataSourceProvider transport switch', () {
    final gateway = _FakeCardsDataSource();
    final direct = _FakeCardsDataSource();

    ProviderContainer containerFor(CardsDataTransport transport) {
      final container = ProviderContainer(
        overrides: [
          cardsDataTransportProvider.overrideWithValue(transport),
          gatewayCardsDataSourceProvider.overrideWith((ref) => gateway),
          directCardsDataSourceProvider.overrideWith((ref) => direct),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('direct transport selects the direct-RPC source', () {
      final container = containerFor(CardsDataTransport.direct);
      expect(container.read(cardsDataSourceProvider), same(direct));
    });

    test('gateway transport selects the cards-api gateway source', () {
      final container = containerFor(CardsDataTransport.gateway);
      expect(container.read(cardsDataSourceProvider), same(gateway));
    });
  });

  group('mapSupabaseError passthrough', () {
    test('returns an already-typed Failure unchanged', () {
      const failure = NotFoundFailure();
      expect(mapSupabaseError(failure), same(failure));
    });

    test('wraps a non-Failure error as UnknownFailure', () {
      expect(mapSupabaseError(Exception('boom')), isA<UnknownFailure>());
    });
  });
}
