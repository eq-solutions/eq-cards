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
  const AuthFlowAwaitingOtp(this.email);
  final String email;
}

class AuthFlowVerifying extends AuthFlowState {
  const AuthFlowVerifying();
}

class AuthFlowError extends AuthFlowState {
  const AuthFlowError(this.message, {this.email = ''});
  final String message;
  // Preserve the email so the OTP screen can retry with the correct address.
  final String email;
}
