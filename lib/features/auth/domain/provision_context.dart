/// Holds the tenant provisioning context when an org admin is creating a new
/// workspace via the /provision?token=<uuid> flow.
///
/// Set by [ProvisionTenantScreen] before navigating to OTP entry; cleared by
/// [OtpScreen] on back/reset or after a successful provision.
class ProvisionContext {
  const ProvisionContext({
    required this.provisionToken,
    this.orgName,
  });

  /// The one-time UUID from shell_control.provision_tokens.
  /// Passed to shell-provision-tenant to atomically create the workspace.
  final String provisionToken;

  /// Optional display name from the ?name= URL param. Shown in UI before
  /// the API call; the authoritative name lives in the token row.
  final String? orgName;

  /// The name to show in UI, falling back to "your organisation" when absent.
  String get displayName =>
      orgName?.isNotEmpty == true ? orgName! : 'your organisation';
}
