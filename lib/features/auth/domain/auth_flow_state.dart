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
  const AuthFlowAwaitingOtp(this.phone);
  final String phone;
}

class AuthFlowVerifying extends AuthFlowState {
  const AuthFlowVerifying();
}

class AuthFlowError extends AuthFlowState {
  const AuthFlowError(this.message);
  final String message;
}
