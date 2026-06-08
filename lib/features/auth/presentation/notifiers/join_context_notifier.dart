import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/join_context.dart';

part 'join_context_notifier.g.dart';

/// Stores the active [JoinContext] while a worker is in the middle of a
/// QR / join-code sign-up flow.
///
/// Null means the user is on the normal sign-in path. Set by
/// [JoinTenantScreen] before navigating to OTP; cleared on back/reset.
@riverpod
class JoinContextNotifier extends _$JoinContextNotifier {
  @override
  JoinContext? build() => null;

  void setContext(JoinContext ctx) => state = ctx;

  void clear() => state = null;
}
