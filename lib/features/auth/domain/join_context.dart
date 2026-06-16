/// Holds the tenant join context when a worker is entering via a QR code or
/// join code — as opposed to the normal sign-in flow where tenant assignment
/// comes from the shell-login-phone-otp exchange.
///
/// Set before OTP entry; read in `OtpScreen._submit` to route the verification
/// through `AuthFlowNotifier.joinTenant` instead of `verifyPhoneOtp`.
class JoinContext {
  const JoinContext({
    required this.tenantSlug,
    this.tenantName,
  });

  /// The URL slug that identifies the tenant, e.g. `sks`.
  final String tenantSlug;

  /// Optional display name — may be absent when the slug was typed manually.
  final String? tenantName;

  /// The name to show in UI, falling back to the slug with first letter
  /// capitalised when no display name is available.
  String get displayName =>
      tenantName?.isNotEmpty == true
          ? tenantName!
          : tenantSlug.isEmpty
              ? 'your team'
              : '${tenantSlug[0].toUpperCase()}${tenantSlug.substring(1)}';
}
