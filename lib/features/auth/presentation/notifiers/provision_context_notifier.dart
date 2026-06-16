import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/provision_context.dart';

part 'provision_context_notifier.g.dart';

/// Stores the active [ProvisionContext] while an org admin is in the middle of
/// the self-serve workspace provisioning flow (/provision?token={uuid}).
///
/// Null means the user is on a normal sign-in or join path. Set by
/// `ProvisionTenantScreen` before navigating to OTP; cleared on back/reset
/// and after a successful provision.
@riverpod
class ProvisionContextNotifier extends _$ProvisionContextNotifier {
  @override
  ProvisionContext? build() => null;

  // ignore: use_setters_to_change_properties -- 'setContext' is more explicit than a property setter on a notifier
  void setContext(ProvisionContext ctx) => state = ctx;

  void clear() => state = null;
}
