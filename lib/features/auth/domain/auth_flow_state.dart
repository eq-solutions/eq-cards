sealed class AuthFlowState {
  const AuthFlowState();
}

class AuthFlowIdle extends AuthFlowState {
  const AuthFlowIdle();
}

class AuthFlowSendingOtp extends AuthFlowState {
  const AuthFlowSendingOtp();
}

class AuthFlowAwaitingOtp extends AuthFlowState {
  const AuthFlowAwaitingOtp.email(this.email) : phone = null;
  const AuthFlowAwaitingOtp.phone(this.phone) : email = null;

  final String? email;
  final String? phone;

  bool get isPhone => phone != null;

  /// The identifier shown to the user in the OTP confirmation copy.
  String get displayTarget => email ?? phone!;
}

class AuthFlowVerifying extends AuthFlowState {
  const AuthFlowVerifying({this.isPhone = false});
  final bool isPhone;
}

class AuthFlowError extends AuthFlowState {
  const AuthFlowError(this.message);
  final String message;
}

/// Emitted by [AuthFlowNotifier.provisionTenant] on successful workspace
/// creation. The OTP screen listens for this state and opens Shell at
/// `core.eq.solutions/:tenantSlug` in an external browser, then returns
/// the user to the Cards sign-in screen.
class AuthFlowProvisionComplete extends AuthFlowState {
  const AuthFlowProvisionComplete(this.tenantSlug);
  final String tenantSlug;
}
