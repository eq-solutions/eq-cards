/// Remembers an invite claim token while the worker completes sign-in.
///
/// A worker who opens `/claim?token=…` while signed out is sent to the phone-OTP
/// flow. When OTP succeeds they have a Supabase session but NO tenant yet — the
/// tenant only arrives once they activate the invite. Without this, the
/// provisioning gate in app_router bounces that tenant-less session straight to
/// the not-provisioned screen, and they never get back to the claim screen to
/// tap "Activate" — a dead-end that forces them to re-open the invite link.
///
/// The claim screen stashes the token here before sending the worker to sign in;
/// the router reads it and returns them to `/claim?token=…` instead of
/// not-provisioned. The activate step clears it on success.
///
/// In-memory is sufficient: the web sign-in flow is client-side navigation (no
/// full page reload), so this survives the round-trip within the session.
class PendingClaim {
  PendingClaim._();

  static String? token;

  static void clear() => token = null;
}
